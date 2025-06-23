# Quick syntax test for deploy.ps1
try {
    $scriptContent = Get-Content "D:\Dev\k8s-exercice\correction\scripts\deploy.ps1" -Raw
    $scriptBlock = [scriptblock]::Create($scriptContent)
    Write-Host "✅ PowerShell script syntax is VALID" -ForegroundColor Green
    
    # Test the help function
    Write-Host "`n🧪 Testing help function..." -ForegroundColor Cyan
    & "D:\Dev\k8s-exercice\correction\scripts\deploy.ps1" help
    
} catch {
    Write-Host "❌ PowerShell script syntax ERROR:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
