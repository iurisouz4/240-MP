#!/usr/bin/env pwsh
# deploy-batocera.ps1 — Sobe o binário e arquivos QML compilados para o Batocera RPi
# Uso: .\scripts\deploy-batocera.ps1 [-Host iuri-rpi] [-Password linux]

param(
    [string]$RpiHost  = "iuri-rpi",
    [string]$Password = "linux",
    [string]$DistDir  = "$PSScriptRoot\..\dist-arm64"
)

$DistDir = Resolve-Path $DistDir
$Binary  = "$DistDir\usr\local\bin\240mp"
$ShareDir = "$DistDir\usr\local\share\240mp"

Write-Host "==> Verificando dist em $DistDir ..."
if (-not (Test-Path $Binary)) {
    Write-Error "Binario nao encontrado: $Binary. Rode o build Docker primeiro."
    exit 1
}

Write-Host "==> Testando conexao SSH com $RpiHost ..."
$sshOpts = "-o StrictHostKeyChecking=no -o ConnectTimeout=15"

function Invoke-Ssh([string]$cmd) {
    $result = & ssh $sshOpts.Split(" ") "root@$RpiHost" $cmd 2>&1
    return $result
}

$test = Invoke-Ssh "echo OK"
if ($test -notmatch "OK") {
    Write-Error "Nao foi possivel conectar em root@$RpiHost. Verifique a rede."
    exit 1
}
Write-Host "    Conectado!"

# Verificar bundle dir no RPi
$bundleDir = (Invoke-Ssh "ls /userdata/240-MP/240mp 2>/dev/null && echo /userdata/240-MP || echo NOTFOUND")
if ($bundleDir -match "NOTFOUND") {
    Write-Host "    Bundle nao encontrado em /userdata/240-MP — criando..."
    Invoke-Ssh "mkdir -p /userdata/240-MP"
    $bundleDir = "/userdata/240-MP"
} else {
    $bundleDir = "/userdata/240-MP"
}

Write-Host "==> Fazendo backup do binario atual ..."
Invoke-Ssh "cp -f /userdata/240-MP/240mp /userdata/240-MP/240mp.bak 2>/dev/null; echo done"

Write-Host "==> Enviando binario arm64 (~$(([System.IO.FileInfo]$Binary).Length/1MB -as [int]) MB) ..."
& scp $sshOpts.Split(" ") "$Binary" "root@${RpiHost}:/userdata/240-MP/240mp.new"
Invoke-Ssh "chmod +x /userdata/240-MP/240mp.new && mv -f /userdata/240-MP/240mp.new /userdata/240-MP/240mp"
Write-Host "    Binario atualizado!"

Write-Host "==> Enviando modulos QML atualizados ..."
$qmlFiles = @(
    "modules\plex\views\Item.qml",
    "modules\jellyfin\views\Item.qml"
)
foreach ($f in $qmlFiles) {
    $localPath = "$ShareDir\$f"
    $remotePath = "/userdata/240-MP/$($f -replace '\\','/')"
    $remoteDir  = ($remotePath -replace '/[^/]+$','')
    Invoke-Ssh "mkdir -p $remoteDir"
    & scp $sshOpts.Split(" ") "$localPath" "root@${RpiHost}:$remotePath"
    Write-Host "    $f -> $remotePath"
}

Write-Host ""
Write-Host "==> Deploy concluido! Para testar no Batocera, abra o app pelo Ports."
