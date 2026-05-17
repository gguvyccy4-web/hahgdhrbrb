# Visual Regression Dashboard Server
# Serves live desktop preview for remote QA review

param(
    [int]$Port = 8080,
    [string]$AuthToken = "visual-test-2024"
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Web

# --- P/Invoke for mouse/keyboard simulation ---
$signature = @'
[DllImport("user32.dll")]
public static extern bool SetCursorPos(int X, int Y);

[DllImport("user32.dll")]
public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, int dwExtraInfo);

[DllImport("user32.dll")]
public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, int dwExtraInfo);

[DllImport("user32.dll")]
public static extern bool GetCursorPos(out POINT lpPoint);

public struct POINT {
    public int X;
    public int Y;
}

public const uint MOUSEEVENTF_LEFTDOWN = 0x02;
public const uint MOUSEEVENTF_LEFTUP = 0x04;
public const uint MOUSEEVENTF_RIGHTDOWN = 0x08;
public const uint MOUSEEVENTF_RIGHTUP = 0x10;
public const uint MOUSEEVENTF_MIDDLEDOWN = 0x20;
public const uint MOUSEEVENTF_MIDDLEUP = 0x40;
public const uint MOUSEEVENTF_WHEEL = 0x0800;
public const uint KEYEVENTF_KEYDOWN = 0x0000;
public const uint KEYEVENTF_KEYUP = 0x0002;
'@

Add-Type -MemberDefinition $signature -Name "Win32Input" -Namespace "NativeMethods"

# --- HTTP Server ---
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:$Port/")
$listener.Start()

Write-Host "[VISUAL] Dashboard server started on port $Port"
Write-Host "[VISUAL] Auth token: $AuthToken"

$screenWidth = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
$screenHeight = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
Write-Host "[VISUAL] Screen resolution: ${screenWidth}x${screenHeight}"

# HTML page served to the browser
$htmlTemplate = @'
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
<title>Visual Regression Dashboard</title>
<style>
*{margin:0;padding:0;box-sizing:border-box;}
body{background:#0d1117;overflow:hidden;font-family:system-ui;touch-action:manipulation;}
#screen{width:100vw;height:auto;display:block;image-rendering:auto;}
#status{position:fixed;top:8px;right:8px;background:rgba(0,0,0,0.8);color:#3fb950;padding:6px 12px;border-radius:16px;font-size:11px;z-index:100;font-family:monospace;}
#toolbar{position:fixed;bottom:16px;left:50%;transform:translateX(-50%);display:flex;gap:8px;z-index:100;background:rgba(22,27,34,0.95);padding:8px 14px;border-radius:24px;border:1px solid #30363d;}
.btn{background:#21262d;color:#c9d1d9;border:1px solid #30363d;padding:10px 14px;border-radius:18px;font-size:12px;cursor:pointer;white-space:nowrap;touch-action:manipulation;}
.btn:active{background:#30363d;}
#text-input{position:fixed;bottom:90px;left:50%;transform:translateX(-50%);z-index:100;display:none;}
#text-input input{background:#161b22;border:1px solid #30363d;color:#c9d1d9;padding:8px 14px;border-radius:18px;font-size:14px;width:70vw;outline:none;}
</style>
</head>
<body>
<img id="screen" src="/screen?t=" alt="Visual Test Dashboard" />
<div id="status">● LIVE</div>
<div id="toolbar">
    <button class="btn" ontouchstart="sendKey('LWin')" onmousedown="sendKey('LWin')">⊞</button>
    <button class="btn" ontouchstart="sendKey('Escape')" onmousedown="sendKey('Escape')">Esc</button>
    <button class="btn" ontouchstart="sendKey('Tab')" onmousedown="sendKey('Tab')">Tab</button>
    <button class="btn" ontouchstart="sendKey('Enter')" onmousedown="sendKey('Enter')">↵</button>
    <button class="btn" ontouchstart="toggleKeyboard()" onmousedown="toggleKeyboard()">⌨</button>
</div>
<div id="text-input"><input id="key-input" type="text" placeholder="Type here..." autocomplete="off" /></div>

<script>
var AUTH = '__AUTH_TOKEN__';
var refreshTimer = null;
var lastClickTime = 0;

function refreshScreen() {
    var img = document.getElementById('screen');
    img.src = '/screen?t=' + Date.now() + '&auth=' + AUTH;
    refreshTimer = setTimeout(refreshScreen, 300);
}

function sendMouseEvent(type, x, y, button) {
    var img = document.getElementById('screen');
    var scaleX = img.naturalWidth / img.clientWidth;
    var scaleY = img.naturalHeight / img.clientHeight;
    var realX = Math.round(x * scaleX);
    var realY = Math.round(y * scaleY);
    
    fetch('/input', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
            type: type, 
            x: realX, 
            y: realY, 
            button: button || 'left',
            auth: AUTH 
        })
    });
}

function sendKey(key) {
    fetch('/input', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type: 'key', key: key, auth: AUTH })
    });
}

function sendText(text) {
    fetch('/input', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type: 'text', text: text, auth: AUTH })
    });
}

function toggleKeyboard() {
    var input = document.getElementById('text-input');
    if (input.style.display === 'block') {
        input.style.display = 'none';
    } else {
        input.style.display = 'block';
        document.getElementById('key-input').focus();
    }
}

document.getElementById('screen').addEventListener('touchstart', function(e) {
    e.preventDefault();
    var touch = e.touches[0];
    var rect = e.target.getBoundingClientRect();
    var x = touch.clientX - rect.left;
    var y = touch.clientY - rect.top;
    sendMouseEvent('down', x, y, 'left');
    lastClickTime = Date.now();
}, { passive: false });

document.getElementById('screen').addEventListener('touchmove', function(e) {
    e.preventDefault();
    var touch = e.touches[0];
    var rect = e.target.getBoundingClientRect();
    var x = touch.clientX - rect.left;
    var y = touch.clientY - rect.top;
    sendMouseEvent('move', x, y, 'left');
}, { passive: false });

document.getElementById('screen').addEventListener('touchend', function(e) {
    e.preventDefault();
    if (Date.now() - lastClickTime < 300) {
        var rect = e.target.getBoundingClientRect();
        var touch = e.changedTouches[0];
        var x = touch.clientX - rect.left;
        var y = touch.clientY - rect.top;
        sendMouseEvent('up', x, y, 'left');
    }
});

document.getElementById('screen').addEventListener('mousedown', function(e) {
    var rect = e.target.getBoundingClientRect();
    sendMouseEvent('down', e.clientX - rect.left, e.clientY - rect.top, 'left');
});

document.getElementById('screen').addEventListener('mousemove', function(e) {
    if (e.buttons === 1) {
        var rect = e.target.getBoundingClientRect();
        sendMouseEvent('move', e.clientX - rect.left, e.clientY - rect.top, 'left');
    }
});

document.getElementById('screen').addEventListener('mouseup', function(e) {
    var rect = e.target.getBoundingClientRect();
    sendMouseEvent('up', e.clientX - rect.left, e.clientY - rect.top, 'left');
});

document.getElementById('screen').addEventListener('wheel', function(e) {
    e.preventDefault();
    sendMouseEvent('scroll', 0, e.deltaY > 0 ? -120 : 120, 'middle');
}, { passive: false });

document.getElementById('key-input').addEventListener('keydown', function(e) {
    if (e.key === 'Enter') {
        sendText(this.value);
        this.value = '';
        toggleKeyboard();
    }
});

window.addEventListener('error', function() {
    document.getElementById('status').textContent = '● RECONNECTING';
    document.getElementById('status').style.color = '#f85149';
});

refreshScreen();
</script>
</body>
</html>
'@

# Replace auth token placeholder
$htmlTemplate = $htmlTemplate.Replace('__AUTH_TOKEN__', $AuthToken)

# --- Request handler ---
while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response
    
    try {
        $path = $request.Url.AbsolutePath
        
        if ($path -eq '/' -or $path -eq '/index.html') {
            # Serve the dashboard HTML
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($htmlTemplate)
            $response.ContentType = "text/html; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        elseif ($path -eq '/screen') {
            # Capture and serve screenshot
            $bitmap = New-Object System.Drawing.Bitmap($screenWidth, $screenHeight)
            $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
            $graphics.CopyFromScreen(0, 0, 0, 0, $bitmap.Size)
            $graphics.Dispose()
            
            $memoryStream = New-Object System.IO.MemoryStream
            $bitmap.Save($memoryStream, [System.Drawing.Imaging.ImageFormat]::Jpeg)
            $bitmap.Dispose()
            
            $bytes = $memoryStream.ToArray()
            $memoryStream.Dispose()
            
            $response.ContentType = "image/jpeg"
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
        }
        elseif ($path -eq '/input' -and $request.HttpMethod -eq 'POST') {
            # Handle mouse/keyboard input
            $reader = New-Object System.IO.StreamReader($request.InputStream)
            $body = $reader.ReadToEnd()
            $reader.Close()
            
            try {
                $inputData = $body | ConvertFrom-Json
                
                if ($inputData.auth -ne $AuthToken) {
                    $response.StatusCode = 403
                }
                else {
                    if ($inputData.type -eq 'move') {
                        [NativeMethods.Win32Input]::SetCursorPos($inputData.x, $inputData.y)
                    }
                    elseif ($inputData.type -eq 'down') {
                        [NativeMethods.Win32Input]::SetCursorPos($inputData.x, $inputData.y)
                        [NativeMethods.Win32Input]::mouse_event(0x02, 0, 0, 0, 0)
                    }
                    elseif ($inputData.type -eq 'up') {
                        [NativeMethods.Win32Input]::SetCursorPos($inputData.x, $inputData.y)
                        [NativeMethods.Win32Input]::mouse_event(0x04, 0, 0, 0, 0)
                    }
                    elseif ($inputData.type -eq 'scroll') {
                        [NativeMethods.Win32Input]::mouse_event(0x0800, 0, 0, [uint32]$inputData.y, 0)
                    }
                    elseif ($inputData.type -eq 'key') {
                        # Send key combination
                        $key = $inputData.key
                        # Simple key mapping
                        $keyMap = @{
                            'LWin' = 0x5B
                            'RWin' = 0x5C
                            'Escape' = 0x1B
                            'Tab' = 0x09
                            'Enter' = 0x0D
                            'Backspace' = 0x08
                            'Delete' = 0x2E
                            'Space' = 0x20
                        }
                        if ($keyMap.ContainsKey($key)) {
                            $vk = $keyMap[$key]
                            [NativeMethods.Win32Input]::keybd_event($vk, 0, 0, 0)
                            Start-Sleep -Milliseconds 50
                            [NativeMethods.Win32Input]::keybd_event($vk, 0, 2, 0)
                        }
                    }
                    elseif ($inputData.type -eq 'text') {
                        # Send text as keystrokes
                        foreach ($char in $inputData.text.ToCharArray()) {
                            $vk = [int][char]$char
                            # Basic ASCII handling
                            if ($vk -ge 32 -and $vk -le 126) {
                                # For uppercase letters and symbols, we need Shift
                                if ($char -match '[A-Z]' -or $char -match '[~!@#$%^&*()_+{}|:"<>?]') {
                                    [NativeMethods.Win32Input]::keybd_event(0x10, 0, 0, 0) # Shift down
                                }
                                [NativeMethods.Win32Input]::keybd_event([byte]$vk, 0, 0, 0)
                                Start-Sleep -Milliseconds 10
                                [NativeMethods.Win32Input]::keybd_event([byte]$vk, 0, 2, 0)
                                if ($char -match '[A-Z]' -or $char -match '[~!@#$%^&*()_+{}|:"<>?]') {
                                    [NativeMethods.Win32Input]::keybd_event(0x10, 0, 2, 0) # Shift up
                                }
                                Start-Sleep -Milliseconds 20
                            }
                        }
                    }
                    
                    $response.StatusCode = 200
                }
            }
            catch {
                $response.StatusCode = 400
            }
            
            $response.ContentLength64 = 0
        }
        else {
            $response.StatusCode = 404
            $response.ContentLength64 = 0
        }
        
        $response.Close()
    }
    catch {
        # Silently continue on request errors
        try { $response.Close() } catch {}
    }
}

$listener.Stop()
