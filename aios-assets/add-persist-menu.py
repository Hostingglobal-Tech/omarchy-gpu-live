# -*- coding: utf-8 -*-
"""부팅 메뉴에 '영구 저장' 항목을 넣는다.

★라이브 ISO 의 쓰기는 기본적으로 RAM 오버레이라 재부팅하면 통째로 사라진다.
  업데이트도, 설정도, 만든 파일도 남지 않는다. USB 에 AIOSDATA 라벨을 가진
  ext4 파티션을 하나 만들어 두면 이 메뉴가 그것을 쓰기 계층으로 삼는다.
  (파티션 만드는 법은 docs/persist.md 참조)

파티션이 없으면 이 메뉴는 부팅에 실패하므로, 기본 메뉴는 그대로 두고
항목을 하나 더 얹는다 — 사람이 골라서 쓴다.
"""
import io, re, sys

MARK = "cow_device="
COW = "cow_device=/dev/disk/by-label/AIOSDATA cow_persistent=P"

def patch_grub(path):
    s = io.open(path, encoding="utf-8", errors="replace").read()
    if MARK in s:
        return "이미 있음"
    m = re.search(r'(menuentry\s+"[^"]*"[^\n]*\{\n(?:.*?\n)*?\}\n)', s)
    if not m:
        return "menuentry 를 못 찾음"
    block = m.group(1)
    if "linux" not in block:
        return "linux 줄이 없음"
    new = re.sub(r'menuentry\s+"([^"]*)"', r'menuentry "\1 - 영구 저장(USB 에 남긴다)"', block, count=1)
    new = new.replace("cow_spacesize=8G", COW)
    if MARK not in new:
        new = new.replace("archisobasedir=", COW + " archisobasedir=", 1)
    s = s[:m.end(1)] + "\n" + new + s[m.end(1):]
    io.open(path, "w", encoding="utf-8").write(s)
    return "추가함"

def patch_syslinux(path):
    s = io.open(path, encoding="utf-8", errors="replace").read()
    if MARK in s:
        return "이미 있음"
    m = re.search(r'(LABEL\s+\S+\n(?:\s+.*\n)+?)(?=LABEL|\Z)', s)
    if not m:
        return "LABEL 을 못 찾음"
    new = re.sub(r'(LABEL\s+)(\S+)', r'\1\2persist', m.group(1), count=1)
    new = re.sub(r'(MENU LABEL\s+)(.*)', r'\1\2 (영구 저장)', new, count=1)
    new = new.replace("cow_spacesize=8G", COW)
    if MARK not in new:
        new = new.replace("archisobasedir=", COW + " archisobasedir=", 1)
    s = s[:m.end(1)] + new + s[m.end(1):]
    io.open(path, "w", encoding="utf-8").write(s)
    return "추가함"

for p in sys.argv[1:]:
    try:
        r = patch_syslinux(p) if "syslinux" in p else patch_grub(p)
    except Exception as e:
        r = "실패: %s" % e
    print("  %-46s %s" % (p.split("/")[-1], r))
