param(
  [string]$Root = 'A:\New folder\OneDrive\Documents\Roblox Scripts',
  [int]$Port = 3000
)

Add-Type -AssemblyName System.Web
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()

try {
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $reqPath = [System.Web.HttpUtility]::UrlDecode($ctx.Request.Url.AbsolutePath.TrimStart('/'))
    if ([string]::IsNullOrWhiteSpace($reqPath)) { $reqPath = 'index.html' }
    $candidate = Join-Path $Root $reqPath
    if ((Test-Path -LiteralPath $candidate) -and -not (Get-Item -LiteralPath $candidate).PSIsContainer) {
      $ext = [System.IO.Path]::GetExtension($candidate).ToLowerInvariant()
      $contentType = switch ($ext) {
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
      $bytes = [System.IO.File]::ReadAllBytes($candidate)
      $ctx.Response.StatusCode = 200
      $ctx.Response.ContentType = $contentType
      $ctx.Response.ContentLength64 = $bytes.Length
      $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    }
    else {
      $msg = [System.Text.Encoding]::UTF8.GetBytes('Not Found')
      $ctx.Response.StatusCode = 404
      $ctx.Response.ContentType = 'text/plain; charset=utf-8'
      $ctx.Response.ContentLength64 = $msg.Length
      $ctx.Response.OutputStream.Write($msg, 0, $msg.Length)
    }
    $ctx.Response.OutputStream.Close()
  }
}
finally {
  $listener.Stop()
  $listener.Close()
}
