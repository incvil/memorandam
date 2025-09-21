#
# exeとdllのバージョンが上がらないとコミットさせない
#
Write-Host "pre-commit script checks file version"
Write-Host "To properly handle file paths containing Japanese character 'git config --global core.quotepath false'"

function SaveHead {
    param(
        [String]$git_file_name,
        [String]$out_file_name
    )

    Write-Host "SaveHead -git_file_name $git_file_name -out_file_name $out_file_name"

    [System.Diagnostics.ProcessStartInfo]$psi = New-Object -TypeName System.Diagnostics.ProcessStartInfo

    $psi.WorkingDirectory = (Get-Location).Path
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $psi.FileName = "git"
    $psi.Arguments = "show HEAD:$git_file_name"

    [System.Diagnostics.Process]$proc = [System.Diagnostics.Process]::Start($psi)
    if (-not $proc) { return }

    ##$proc.WaitForExit()

    $fileStreamWrite = [System.IO.FileStream]::new($out_file_name, [System.IO.FileMode]::Create)
    $proc.StandardOutput.BaseStream.CopyTo($fileStreamWrite)
    #Write-Host "len:$($fileStreamWrite.Length)"
    $fileStreamWrite.Close()
    $proc.Dispose()
}


$ErrorActionPreference = "Stop"

# コミット予定の dll/exe を取得

$staged = git diff --cached --name-only --diff-filter=ACM
$files = $staged | Where-Object { $_ -match "\w.dll" }
#Write-Host "$files"

$tmpFile = New-TemporaryFile
if (Test-Path $tmpFile) {
    #Write-Host "tmp file exists:$tmpFile"
}


foreach ($file in $files) {
    #Write-Host "checking $file"
    if (-not (Test-Path $file)) { continue }

    # 現在のファイルのバージョン
    try {
        $newVer = (Get-Item $file).VersionInfo.FileVersion
    } catch {
        continue
    }
    #Write-Host "verion of new file is $newVer"

    # git管理下の前回のバージョンを tmp に保存

    SaveHead -git_file_name $file -out_file_name $tmpFile

    try {
        $oldVer = (Get-Item $tmpFile).VersionInfo.FileVersion
    } catch {
        continue
    }

    if ($newVer -gt $oldVer) {
        Write-Host "Version of $file changed from $oldVer to $newVer."
    } else {
        Write-Host "Since version of $file is not grater($NewVer), quit to commit."
        exit 1
    }
}

Remove-Item $tmpFile -Force

exit 0

