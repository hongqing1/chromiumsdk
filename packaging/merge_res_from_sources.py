#!/usr/bin/env python3
"""Merge Android res files from Chromium .res.sources (+ extras) into one tree.

Values XML files with the same dest path are merged (children of <resources>).
Same (tag, name[, type]) with identical body is OK; conflicts abort.
Non-values files: identical overwrite OK; content conflict aborts.
"""
from __future__ import annotations

import re
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

# Android resource XML often uses unbound prefixes (tools:); keep them.
ET.register_namespace("android", "http://schemas.android.com/apk/res/android")
ET.register_namespace("tools", "http://schemas.android.com/tools")
ET.register_namespace("app", "http://schemas.android.com/apk/res-auto")


def is_values_path(dest_rel: str) -> bool:
    # values, values-night, values-sw600dp, ...
    parts = Path(dest_rel).parts
    return bool(parts) and parts[0].startswith("values")


def dest_rel_from_src(srcf: Path) -> str:
    s = str(srcf)
    for marker in ("/res_webkit/", "/res/"):
        if marker in s:
            return s.split(marker, 1)[1]
    return srcf.name


def child_key(elem: ET.Element) -> tuple:
    tag = elem.tag.split("}")[-1] if "}" in elem.tag else elem.tag
    name = elem.get("name") or ""
    typ = elem.get("type") or ""
    return (tag, name, typ)


def child_signature(elem: ET.Element) -> str:
    """Normalize element text for equality (ignore formatting)."""
    # Serialize without NS map noise where possible
    raw = ET.tostring(elem, encoding="unicode")
    return re.sub(r"\s+", " ", raw).strip()


def merge_values_xml(existing: Path, incoming: bytes, label: str) -> None:
    if not existing.exists():
        existing.parent.mkdir(parents=True, exist_ok=True)
        existing.write_bytes(incoming)
        return
    try:
        old_root = ET.parse(existing).getroot()
        new_root = ET.fromstring(incoming)
    except ET.ParseError as e:
        raise SystemExit(f"XML parse error merging {existing} <- {label}: {e}")

    if old_root.tag.split("}")[-1] != "resources" or new_root.tag.split("}")[-1] != "resources":
        raise SystemExit(f"Expected <resources> root when merging {existing} <- {label}")

    # Preserve/union attributes on root (xmlns etc. already in tag via parser)
    for k, v in new_root.attrib.items():
        if k not in old_root.attrib:
            old_root.set(k, v)

    index = {}
    for ch in list(old_root):
        index[child_key(ch)] = ch

    for ch in list(new_root):
        key = child_key(ch)
        if key[1] == "" and key[0] in ("!--",):  # comments skipped by ET
            continue
        if key in index and key[1]:  # named resource
            if child_signature(index[key]) != child_signature(ch):
                raise SystemExit(
                    f"CONFLICT {existing.as_posix()} resource {key} differs from {label}\n"
                    f"  have: {child_signature(index[key])[:200]}\n"
                    f"  new:  {child_signature(ch)[:200]}"
                )
            # same — keep existing
            continue
        if key in index and not key[1]:
            # unnamed (e.g. eat-comment) — append duplicates OK; skip identical
            if child_signature(index[key]) == child_signature(ch):
                continue
        old_root.append(ch)
        index[key] = ch

    # Write with XML declaration
    existing.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n' + ET.tostring(old_root, encoding="unicode") + "\n",
        encoding="utf-8",
    )


def copy_or_merge(srcf: Path, dest: Path, dest_rel: str, label: str, stats: dict) -> None:
    data = srcf.read_bytes()
    if is_values_path(dest_rel) and dest_rel.endswith(".xml"):
        if dest.exists():
            merge_values_xml(dest, data, label)
            stats["merged"] += 1
        else:
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data)
            stats["copied"] += 1
        return
    if dest.exists():
        if dest.read_bytes() == data:
            stats["dup_ok"] += 1
            return
        raise SystemExit(f"CONFLICT non-values file {dest_rel}: {label} vs existing")
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    stats["copied"] += 1


def ingest_sources_file(out: Path, sources: Path, dest_root: Path, stats: dict) -> None:
    if not sources.is_file():
        print("WARN: no", sources)
        stats["missing_sources"] += 1
        return
    for rel in sources.read_text().splitlines():
        rel = rel.strip()
        if not rel:
            continue
        srcf = (out / rel).resolve()
        if not srcf.is_file():
            # also try as path relative to src root (out/../..)
            alt = (out / rel).resolve()
            print("WARN: missing", rel, "->", srcf)
            stats["missing_files"] += 1
            continue
        dest_rel = dest_rel_from_src(srcf)
        # Normalize res_webkit into normal res/
        if dest_rel.startswith("layout/") or dest_rel.startswith("menu/") or "/" in dest_rel:
            pass
        dest = dest_root / dest_rel
        copy_or_merge(srcf, dest, dest_rel, str(sources.name) + ":" + rel, stats)


def ingest_file(srcf: Path, dest_rel: str, dest_root: Path, stats: dict, label: str) -> None:
    if not srcf.is_file():
        print("WARN: missing extra", srcf)
        stats["missing_files"] += 1
        return
    copy_or_merge(srcf, dest_root / dest_rel, dest_rel, label, stats)


def ingest_resources_zip(zip_path: Path, dest_root: Path, stats: dict, strip_prefixes=("0_res/", "0_res_webkit/")) -> None:
    if not zip_path.is_file():
        print("WARN: no zip", zip_path)
        stats["missing_sources"] += 1
        return
    with zipfile.ZipFile(zip_path) as zf:
        for info in zf.infolist():
            if info.is_dir():
                continue
            name = info.filename
            dest_rel = name
            for p in strip_prefixes:
                if dest_rel.startswith(p):
                    dest_rel = dest_rel[len(p) :]
                    break
            # grit zips use values-xx/... directly
            if dest_rel.endswith("/"):
                continue
            data = zf.read(info)
            dest = dest_root / dest_rel
            # write via temp file path helper
            if is_values_path(dest_rel) and dest_rel.endswith(".xml"):
                if dest.exists():
                    merge_values_xml(dest, data, zip_path.name + ":" + name)
                    stats["merged"] += 1
                else:
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    dest.write_bytes(data)
                    stats["copied"] += 1
            else:
                if dest.exists():
                    if dest.read_bytes() == data:
                        stats["dup_ok"] += 1
                        continue
                    raise SystemExit(f"CONFLICT from zip {zip_path.name}:{name}")
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(data)
                stats["copied"] += 1


def main() -> None:
    out = Path(sys.argv[1])
    dest_root = Path(sys.argv[2])
    src_root = out.parent.parent  # out/crwebview_arm64 -> src
    dest_root.mkdir(parents=True, exist_ok=True)

    stats = dict(copied=0, merged=0, dup_ok=0, missing_sources=0, missing_files=0)

    sources_list = [
        out / "gen/android_webview/crwebview_ui_android_resources.res.sources",
        out / "gen/android_webview/crwebview_content_resources.res.sources",
        out / "gen/android_webview/crwebview_embedder_support_resources.res.sources",
        out / "gen/android_webview/resources.res.sources",
        out / "gen/android_webview/crwebview/webkit_glue_resources.res.sources",
        out / "gen/components/autofill/android/autofill_java_resources.res.sources",
        out / "gen/media/base/android/media_java_resources.res.sources",
    ]
    for sources in sources_list:
        ingest_sources_file(out, sources, dest_root, stats)

    # autofill dimens reference chip_icon_size / keyboard_accessory_bar_item_icon_width
    # from browser_ui shared_with_webview (dep of autofill, not in the 7 .res.sources).
    shared = (
        src_root
        / "components/browser_ui/widget/android/shared_with_webview/java/res/values/dimens.xml"
    )
    ingest_file(shared, "values/dimens.xml", dest_root, stats, "shared_with_webview")

    # Layouts reference grit strings not listed in the java .res.sources.
    string_zips = [
        out / "obj/android_webview/crwebview_content_strings_grd.resources.zip",
        out / "obj/android_webview/crwebview_web_contents_delegate_strings_grd.resources.zip",
        # ui strings not referenced by layouts in the 7 targets, but cheap & keeps parity
        out / "obj/android_webview/crwebview_ui_strings_grd.resources.zip",
        out / "obj/components/autofill/android/autofill_strings_grd.resources.zip",
    ]
    for z in string_zips:
        ingest_resources_zip(z, dest_root, stats)

    print(
        "merge_res stats:",
        f"copied={stats['copied']}",
        f"merged={stats['merged']}",
        f"dup_ok={stats['dup_ok']}",
        f"missing_sources={stats['missing_sources']}",
        f"missing_files={stats['missing_files']}",
    )
    n = sum(1 for _ in dest_root.rglob("*") if _.is_file())
    print("dest file count:", n)
    styles = dest_root / "values/styles.xml"
    if styles.is_file():
        text = styles.read_text(encoding="utf-8", errors="replace")
        nstyles = len(re.findall(r"<style\s", text))
        print(f"styles.xml style count: {nstyles} bytes={styles.stat().st_size}")
        if nstyles < 5:
            raise SystemExit("styles.xml still nearly empty — merge failed")
    else:
        raise SystemExit("styles.xml missing after merge")


if __name__ == "__main__":
    main()
