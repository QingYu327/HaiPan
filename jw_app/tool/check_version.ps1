# 发布前版本一致性检查：pubspec.yaml 的 version 必须与 Release tag 一致。
# 用法：
#   .\tool\check_version.ps1
#   .\tool\check_version.ps1 -Tag v1.0.1+4144
param(
  [string]$Tag = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pubspecPath = Join-Path $root 'pubspec.yaml'
if (-not (Test-Path $pubspecPath)) {
  Write-Error "找不到 $pubspecPath"
  exit 1
}

$raw = Get-Content $pubspecPath -Raw
$m = [regex]::Match($raw, '(?m)^version:\s*(\d+(?:\.\d+)*)\+(\d+)\s*$')
if (-not $m.Success) {
  Write-Error 'pubspec.yaml 的 version 必须形如 1.0.1+4144'
  exit 1
}
$version = $m.Groups[1].Value
$build = [int]$m.Groups[2].Value
Write-Host "pubspec: $version+$build"

if ($Tag) {
  $normalized = $Tag.Trim()
  if ($normalized.StartsWith('v')) {
    $normalized = $normalized.Substring(1)
  }
  $tm = [regex]::Match($normalized, '^(\d+(?:\.\d+)*)\+(\d+)$')
  if (-not $tm.Success) {
    Write-Error "Release tag 必须形如 v1.0.1+4144，当前：$Tag"
    exit 1
  }
  $tagVersion = $tm.Groups[1].Value
  $tagBuild = [int]$tm.Groups[2].Value
  if ($tagVersion -ne $version -or $tagBuild -ne $build) {
    Write-Error "tag $Tag 与 pubspec $version+$build 不一致"
    exit 1
  }
  Write-Host "tag 校验通过: $Tag"
}

Write-Host '版本一致性检查通过'
