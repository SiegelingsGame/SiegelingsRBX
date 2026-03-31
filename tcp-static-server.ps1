param(
  [string]$Root = 'A:\New folder\OneDrive\Documents\Roblox Scripts',
  [int]$Port = 3000
)

function Get-ContentType([string]$path) {
  switch ([System.IO.Path]::GetExtension($path).ToLowerInvariant()) {
    '.html' { 'text/html; charset=utf-8' }
    '.css'  { 'text/css; charset=utf-8' }
    '.js'   { 'application/javascript; charset=utf-8' }
    '.json' { 'application/json; charset=utf-8' }
    '.png'  { 'image/png' }
    '.jpg'  { 'image/jpeg' }
    '.jpeg' { 'image/jpeg' }
    '.svg'  { 'image/svg+xml' }
    default { 'application/octet-stream' }
  }
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse('127.0.0.1'), $Port)
$listener.Start()

try {
  while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
      $stream = $client.GetStream()
      $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
      $requestLine = $reader.ReadLine()
      if ([string]::IsNullOrWhiteSpace($requestLine)) {
        $client.Close()
        continue
      }

      while (($line = $reader.ReadLine()) -ne $null -and $line -ne '') { }

      $parts = $requestLine.Split(' ')
      $rawPath = if ($parts.Length -ge 2) { $parts[1] } else { '/' }
      $path = [System.Uri]::UnescapeDataString($rawPath.Split('?')[0])

      if ($path -eq '/' -or [string]::IsNullOrWhiteSpace($path)) {
        $path = '/sieglinq-menu-mockup.html'
      }

      $rel = $path.TrimStart('/').Replace('/', '\')
      $full = [System.IO.Path]::GetFullPath((Join-Path $Root $rel))
      $rootFull = [System.IO.Path]::GetFullPath($Root)

      if ($full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $full) -and -not (Get-Item -LiteralPath $full).PSIsContainer) {
        $bytes = [System.IO.File]::ReadAllBytes($full)
        $contentType = Get-ContentType $full
        $header = "HTTP/1.1 200 OK`r`nContent-Type: $contentType`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
        $h = [System.Text.Encoding]::ASCII.GetBytes($header)
        $stream.Write($h, 0, $h.Length)
        $stream.Write($bytes, 0, $bytes.Length)
      }
      else {
        $body = [System.Text.Encoding]::UTF8.GetBytes('Not Found')
        $header = "HTTP/1.1 404 Not Found`r`nContent-Type: text/plain; charset=utf-8`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
        $h = [System.Text.Encoding]::ASCII.GetBytes($header)
        $stream.Write($h, 0, $h.Length)
        $stream.Write($body, 0, $body.Length)
      }

      $stream.Flush()
      $reader.Dispose()
      $stream.Dispose()
    }
    finally {
      $client.Close()
    }
  }
}
finally {
  $listener.Stop()
}
