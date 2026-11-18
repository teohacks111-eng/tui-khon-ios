[CmdletBinding()]
param(
    [ValidateSet("debug", "release")]
    [string]$Configuration = "debug"
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command "wsl.exe" -ErrorAction SilentlyContinue)) {
    throw "Không tìm thấy wsl.exe. Hãy cài và khởi động WSL2 Ubuntu trước."
}

# The project path is intentionally explicit and matches the location approved by the user.
$projectWslPath = "/mnt/c/Users/taoha/AI_Documents/ChiTieu"
$wslCommand = "cd $projectWslPath && BUILD_CONFIGURATION=$Configuration bash ./build-ipa.sh"

& wsl.exe -- bash -lc $wslCommand
if ($LASTEXITCODE -ne 0) {
    throw "Build/test thất bại trong WSL (exit code $LASTEXITCODE)."
}

Write-Host "Hoàn tất. IPA unsigned được lưu trong thư mục artifacts của dự án." -ForegroundColor Green
