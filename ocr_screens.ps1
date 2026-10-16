# PowerShell script to run native Windows OCR on screenshots using approved verbs
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTaskGeneric = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { 
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' 
} | Select-Object -First 1

function Wait-WinRt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $AsyncOp,
        [Parameter(Mandatory = $true)]
        [type]$ResultType
    )

    $method = $asTaskGeneric.MakeGenericMethod($ResultType)
    $task = $method.Invoke($null, @($AsyncOp))
    $task.Wait()
    return $task.Result
}

[Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType=WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics, ContentType=WindowsRuntime] | Out-Null
[Windows.Media.Ocr.OcrEngine, Windows.Media.Ocr, ContentType=WindowsRuntime] | Out-Null

function Get-OcrText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $fileOp = [Windows.Storage.StorageFile]::GetFileFromPathAsync($Path)
        $file = Wait-WinRt -AsyncOp $fileOp -ResultType ([Windows.Storage.StorageFile])
        
        $streamOp = $file.OpenAsync([Windows.Storage.FileAccessMode]::Read)
        $stream = Wait-WinRt -AsyncOp $streamOp -ResultType ([Windows.Storage.Streams.IRandomAccessStream])
        
        $decoderOp = [Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)
        $decoder = Wait-WinRt -AsyncOp $decoderOp -ResultType ([Windows.Graphics.Imaging.BitmapDecoder])
        
        $bitmapOp = $decoder.GetSoftwareBitmapAsync()
        $bitmap = Wait-WinRt -AsyncOp $bitmapOp -ResultType ([Windows.Graphics.Imaging.SoftwareBitmap])
        
        $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
        $ocrOp = $engine.RecognizeAsync($bitmap)
        $result = Wait-WinRt -AsyncOp $ocrOp -ResultType ([Windows.Media.Ocr.OcrResult])
        
        return $result.Text
    } catch {
        return "ERROR: $_"
    }
}

$screensDir = Join-Path $PSScriptRoot "assets\screens"
if (Test-Path $screensDir) {
    Get-ChildItem -Path $screensDir -Recurse -Filter "*.png" | ForEach-Object {
        $txt = Get-OcrText -Path $_.FullName
        $shortTxt = ($txt -replace '\s+', ' ')
        if ($shortTxt.Length -gt 150) { $shortTxt = $shortTxt.Substring(0, 150) }
        Write-Output "$($_.Name) -> $shortTxt"
    }
}
