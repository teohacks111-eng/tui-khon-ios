[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ipaPath = Join-Path $PSScriptRoot "artifacts\TuiKhon-debug.ipa"

if (-not (Test-Path -LiteralPath $ipaPath -PathType Leaf)) {
    throw "Không tìm thấy IPA tại: $ipaPath"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$file = Get-Item -LiteralPath $ipaPath
$zip = [System.IO.Compression.ZipFile]::OpenRead($ipaPath)

try {
    $names = @($zip.Entries | ForEach-Object { $_.FullName })
    $appInfo = $names | Where-Object { $_ -match '^Payload/[^/]+\.app/Info\.plist$' } | Select-Object -First 1
    $appBinary = $names | Where-Object { $_ -match '^Payload/[^/]+\.app/[^/]+$' -and $_ -notmatch 'Info\.plist$' } | Select-Object -First 1

    if (-not $appInfo) {
        throw "IPA không có Payload/<App>.app/Info.plist."
    }
    if (-not $appBinary) {
        throw "IPA không có executable bên trong .app."
    }

    $infoEntry = $zip.GetEntry($appInfo)
    $reader = [System.IO.StreamReader]::new($infoEntry.Open())
    try {
        $infoXml = $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
    }

    [xml]$infoDocument = $infoXml
    $plistNodes = @($infoDocument.plist.dict.ChildNodes | Where-Object {
        $_.NodeType -eq [System.Xml.XmlNodeType]::Element
    })
    $permissionValues = @{}
    for ($index = 0; $index -lt $plistNodes.Count - 1; $index++) {
        if ($plistNodes[$index].Name -eq "key" -and $plistNodes[$index + 1].Name -eq "string") {
            $permissionValues[$plistNodes[$index].InnerText] = $plistNodes[$index + 1].InnerText
        }
    }

    $requiredPermissions = @(
        "NSCameraUsageDescription",
        "NSMicrophoneUsageDescription",
        "NSSpeechRecognitionUsageDescription",
        "NSPhotoLibraryUsageDescription",
        "NSFaceIDUsageDescription"
    )
    foreach ($key in $requiredPermissions) {
        if ([string]::IsNullOrWhiteSpace($permissionValues[$key])) {
            throw "IPA thiếu mô tả quyền hoặc nội dung rỗng: $key"
        }
        Write-Output "PERMISSION_KEY=$key; STATUS=PRESENT"
    }

    $signatureFiles = @($names | Where-Object {
        $_ -match '/_CodeSignature/' -or $_ -match '(^|/)embedded\.mobileprovision$'
    })

    if ($signatureFiles.Count -gt 0) {
        throw "IPA có dấu hiệu chứa chữ ký/provisioning, không đúng cấu hình unsigned."
    }

    $hash = (Get-FileHash -LiteralPath $ipaPath -Algorithm SHA256).Hash
    Write-Output "IPA_PATH=$($file.FullName)"
    Write-Output "SIZE_BYTES=$($file.Length)"
    Write-Output "SHA256=$hash"
    Write-Output "APP_INFO=$appInfo"
    Write-Output "APP_EXECUTABLE=$appBinary"
    Write-Output "SIGNATURE_FILES=$($signatureFiles.Count)"
    Write-Output "IPA_VALIDATION=PASS"
}
finally {
    $zip.Dispose()
}
