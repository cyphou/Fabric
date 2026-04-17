$token = az account get-access-token --resource "https://api.fabric.microsoft.com" --query accessToken -o tsv
$h = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }
$ws = "30da17ec-c32a-4861-bc39-65c5775a87c8"
$sm = "1bb5bdb2-9318-497f-8ebe-39947fd12a79"

# Trigger enhanced refresh
Write-Host "Triggering semantic model refresh..."
$body = @{
    type = "Full"
    commitMode = "transactional"
    applyRefreshPolicy = $false
} | ConvertTo-Json

try {
    $r = Invoke-WebRequest -Uri "https://api.fabric.microsoft.com/v1/workspaces/$ws/semanticModels/$sm/refresh" -Headers $h -Method Post -Body $body -UseBasicParsing
    Write-Host "Status: $($r.StatusCode)"
    if ($r.Headers['x-ms-operation-id']) {
        Write-Host "OpId: $($r.Headers['x-ms-operation-id'])"
    }
    Write-Host "Response: $($r.Content)"
} catch {
    $e = $_.Exception
    Write-Host "Error: $($e.Message)"
    if ($e.Response) {
        $sr = [System.IO.StreamReader]::new($e.Response.GetResponseStream())
        Write-Host "Body: $($sr.ReadToEnd())"
    }
}
