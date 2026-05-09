# ============================================================
#  ServerCore - Windows Docker Desktop 자동 설치 / 셋업
#
#  사용법:
#    setup_docker_windows.bat          (정상 호출)
#    powershell -File setup_docker_windows.ps1
#
#  종료 코드:
#    0  모든 단계 성공
#    1  일반 에러
#    2  CPU 가상화 비활성 (BIOS 활성화 필요)
#    3  Windows 버전 미달 (build 19041 미만)
#   10  WSL 설치됨 - 재부팅 후 재실행 필요
#   11  Docker Desktop 설치됨 - 재부팅 권장
#   20  Docker daemon이 90초 내 응답 없음 (GUI 라이선스 동의 필요)
#   99  elevation 실패 / 무한 루프 가드 발동
# ============================================================

[CmdletBinding()]
param(
    [switch]$Elevated
)

$ErrorActionPreference = 'Stop'

# 콘솔 출력 인코딩을 UTF-8로 강제 — 한글이 깨지지 않도록
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
    $OutputEncoding = [System.Text.UTF8Encoding]::new()
} catch { }

# ─── 출력 헬퍼 ──────────────────────────────────────────────
function Write-Step($n, $msg) { Write-Host "[$n/8] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)       { Write-Host "  [OK] $msg"   -ForegroundColor Green }
function Write-Info($msg)     { Write-Host "  [INFO] $msg" -ForegroundColor Yellow }
function Write-Warn2($msg)    { Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Fail($msg)     { Write-Host "  [FAIL] $msg" -ForegroundColor Red }

function Stop-WithCode([int]$code) {
    # elevation 으로 새로 띄운 창에서는 결과를 사용자가 볼 수 있도록 일시정지
    if ($Elevated) {
        Write-Host ""
        Read-Host "Enter 키를 눌러 종료"
    }
    exit $code
}

# ─── [1] 관리자 권한 확인 / 자체 elevation ───────────────────
function Test-IsAdmin {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = [System.Security.Principal.WindowsPrincipal]::new($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    if ($Elevated) {
        # 이미 elevation을 시도했는데도 admin이 아님 → 무한 루프 방지를 위해 즉시 종료
        Write-Fail "Elevated 프로세스인데 관리자 권한이 없습니다. 무한 루프 방지를 위해 종료합니다."
        Write-Host "         UAC 정책 또는 그룹 정책을 확인하세요."
        Stop-WithCode 99
    }

    Write-Info "관리자 권한 요청 중... (UAC 프롬프트 수락 필요)"

    $scriptPath = $PSCommandPath
    if (-not $scriptPath) { $scriptPath = $MyInvocation.MyCommand.Definition }
    $workDir = Split-Path -Parent $scriptPath

    try {
        Start-Process -FilePath 'powershell.exe' `
            -ArgumentList @(
                '-NoProfile',
                '-ExecutionPolicy', 'Bypass',
                '-File', "`"$scriptPath`"",
                '-Elevated'
            ) `
            -WorkingDirectory $workDir `
            -Verb RunAs | Out-Null
    } catch {
        Write-Fail "UAC 거부 또는 elevation 실패: $($_.Exception.Message)"
        exit 1
    }
    # 원본(비elevated) 프로세스는 즉시 종료. 새 창에서 작업 계속.
    exit 0
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  ServerCore - Docker Desktop Setup (Windows)"             -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ─── [2] CPU 가상화(BIOS) 점검 ──────────────────────────────
Write-Step 2 "CPU 가상화(BIOS) 점검..."
try {
    $procs = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
    $vtx = $true
    foreach ($p in $procs) {
        if (-not $p.VirtualizationFirmwareEnabled) { $vtx = $false; break }
    }
} catch {
    Write-Warn2 "Win32_Processor 조회 실패: $($_.Exception.Message). 점검을 건너뜀."
    $vtx = $true
}
if (-not $vtx) {
    Write-Fail "CPU 가상화가 BIOS에서 비활성 상태입니다."
    Write-Host "         BIOS 진입 후 'Intel VT-x' 또는 'AMD-V (SVM Mode)' 활성화 후 재시도하세요."
    Stop-WithCode 2
}
Write-Ok "Virtualization Enabled"

# ─── [3] Windows 빌드 점검 ──────────────────────────────────
Write-Step 3 "Windows 빌드 점검 (19041 이상 필요)..."
$build = [System.Environment]::OSVersion.Version.Build
if ($build -lt 19041) {
    Write-Fail "Windows build $build 너무 오래됨. Windows Update로 2004(19041) 이상으로 업데이트 필요."
    Stop-WithCode 3
}
Write-Ok "Windows build $build"

# ─── [4] WSL + Ubuntu 점검 ──────────────────────────────────
# WSL2 는 본질적으로 2단계 설치:
#   (A) Windows features (WSL + VirtualMachinePlatform) → 재부팅 필수
#   (B) WSL2 kernel + 배포판(Ubuntu) 등록               → 재부팅 후
#
# 검출 방식 주의: 'wsl --status' 는 구형 inbox wsl.exe 에서 features+kernel
# 활성화 후에도 비-0 으로 빠지는 경우가 있어 신뢰 불가.
# → 'Get-WindowsOptionalFeature' 로 실제 feature 상태를 직접 확인하는
#   방식으로 변경. 이게 source of truth.
Write-Step 4 "WSL + Ubuntu 상태 점검..."

$env:WSL_UTF8 = '1'

function Get-WslHelpText {
    try {
        $raw = & wsl.exe --help 2>&1 | Out-String
        return ($raw -replace "`0", '')
    } catch {
        return ''
    }
}

function Test-WslFeaturesEnabled {
    try {
        $wsl = (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction Stop).State
        $vmp = (Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform           -ErrorAction Stop).State
        Write-Host "    Microsoft-Windows-Subsystem-Linux : $wsl" -ForegroundColor DarkGray
        Write-Host "    VirtualMachinePlatform            : $vmp" -ForegroundColor DarkGray
        return ($wsl -eq 'Enabled' -and $vmp -eq 'Enabled')
    } catch {
        Write-Warn2 "Get-WindowsOptionalFeature 실패: $($_.Exception.Message)"
        return $false
    }
}

# Phase 1: 두 Windows feature 가 활성화돼 있는지 확인
if (-not (Test-WslFeaturesEnabled)) {
    Write-Info "WSL features 비활성. 1단계: DISM 으로 활성화..."
    & dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
    $ec1 = $LASTEXITCODE
    & dism.exe /online /enable-feature /featurename:VirtualMachinePlatform        /all /norestart
    $ec2 = $LASTEXITCODE
    # DISM: 0=success, 3010=success(reboot required) — 둘 다 성공으로 취급
    if (-not (($ec1 -eq 0 -or $ec1 -eq 3010) -and ($ec2 -eq 0 -or $ec2 -eq 3010))) {
        Write-Fail "DISM 실패 (WSL=$ec1, VirtualMachinePlatform=$ec2)."
        Stop-WithCode 1
    }

    Write-Host ""
    Write-Host "  [REBOOT REQUIRED] 1단계 완료. *재부팅 후* 같은 .bat 을 다시 실행하세요." -ForegroundColor Yellow
    Write-Host "                    (재실행 시 WSL2 커널 + Ubuntu 가 자동 설치됩니다)"     -ForegroundColor Yellow
    Stop-WithCode 10
}
Write-Ok "WSL features 활성화 확인"

# Phase 2: 커널 최신화 (필요한 경우 자동 다운로드/설치)
Write-Info "WSL2 커널 최신화 (wsl --update)..."
& wsl.exe --update 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

# 사용자 distro (docker-desktop 제외) 가 있는지 확인
$hasUserDistro = $false
$listRaw = & wsl.exe --list --quiet 2>$null
if ($LASTEXITCODE -eq 0 -and $listRaw) {
    $userDistros = @($listRaw) `
        | ForEach-Object { ($_ -replace "[`0`r`n]", '').Trim() } `
        | Where-Object   { $_ -and ($_ -notmatch '^docker-desktop') }
    if ($userDistros.Count -gt 0) { $hasUserDistro = $true }
}

if (-not $hasUserDistro) {
    Write-Info "Ubuntu 미설치 → 등록..."

    # WSL2 default 보장 (Ubuntu 가 WSL1 으로 등록되는 것을 막기 위해)
    & wsl.exe --set-default-version 2 *>$null

    $help = Get-WslHelpText
    if ($help -match '--no-launch') {
        Write-Info "  (--no-launch 사용: Ubuntu 첫 사용자 셋업 창 자동 스폰 차단)"
        & wsl.exe --install -d Ubuntu --no-launch
    } else {
        Write-Info "  (--no-launch 미지원: Ubuntu 첫 사용자 셋업 창이 별도로 뜰 수 있음. 닫아도 무방)"
        & wsl.exe --install -d Ubuntu
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Fail "wsl --install -d Ubuntu 실패 (exit $LASTEXITCODE)."
        Write-Host "         수동 단계가 필요할 수 있음:"                                                 -ForegroundColor Yellow
        Write-Host "           1) https://aka.ms/wsl2kernel 에서 'WSL2 Linux kernel update' 다운로드/설치" -ForegroundColor Yellow
        Write-Host "           2) wsl --set-default-version 2"                                            -ForegroundColor Yellow
        Write-Host "           3) Microsoft Store 에서 Ubuntu 설치 (또는 wsl --install -d Ubuntu 재시도)" -ForegroundColor Yellow
        Stop-WithCode 1
    }
    Write-Ok "Ubuntu 설치 완료 (Docker 사용엔 첫 사용자 셋업 불필요. 필요시: wsl -d Ubuntu)"
} else {
    Write-Ok "WSL + Ubuntu 정상"
}

# ─── [5] Docker Desktop 설치 점검 ───────────────────────────
function Install-DockerDesktopManually {
    Write-Info "Docker Desktop Installer 다운로드 중..."
    $url = 'https://desktop.docker.com/win/main/amd64/Docker Desktop Installer.exe'
    $tmp = Join-Path $env:TEMP 'DockerInstaller.exe'
    try {
        $oldPref = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
        $ProgressPreference = $oldPref
    } catch {
        Write-Fail "다운로드 실패: $($_.Exception.Message)"
        return $false
    }
    Write-Info "사일런트 설치 진행 (수 분 소요)..."
    try {
        $proc = Start-Process -FilePath $tmp -ArgumentList @('install','--quiet','--accept-license') -Wait -PassThru
    } catch {
        Write-Fail "인스톨러 실행 실패: $($_.Exception.Message)"
        Remove-Item -Force -ErrorAction SilentlyContinue $tmp
        return $false
    }
    Remove-Item -Force -ErrorAction SilentlyContinue $tmp
    if ($proc.ExitCode -ne 0) {
        Write-Fail "인스톨러 종료 코드 $($proc.ExitCode)"
        return $false
    }
    return $true
}

Write-Step 5 "Docker Desktop 설치 점검..."
$dockerExe       = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
$dockerInstalled = (Get-Command docker -ErrorAction SilentlyContinue) -or (Test-Path $dockerExe)

if (-not $dockerInstalled) {
    Write-Info "Docker Desktop 미설치. 설치 시도..."
    $installed = $false
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Info "winget 으로 설치 중..."
        & winget install --id=Docker.DockerDesktop -e --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -eq 0) {
            $installed = $true
        } else {
            Write-Warn2 "winget 실패 (exit $LASTEXITCODE). 수동 다운로드로 fallback..."
        }
    } else {
        Write-Info "winget 미존재. 수동 다운로드로 설치..."
    }
    if (-not $installed) {
        if (-not (Install-DockerDesktopManually)) {
            Stop-WithCode 1
        }
    }
    Write-Host ""
    Write-Host "  [REBOOT RECOMMENDED] Docker Desktop 설치 완료. 재부팅 후 같은 .bat 재실행 권장." -ForegroundColor Yellow
    Stop-WithCode 11
}
Write-Ok "Docker Desktop 설치 확인"

# ─── [6] Docker Desktop 시작 ────────────────────────────────
Write-Step 6 "Docker Desktop 시작..."
$running = Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue
if (-not $running) {
    if (Test-Path $dockerExe) {
        Start-Process -FilePath $dockerExe | Out-Null
        Write-Info "시작 명령 발송. 라이선스 동의 GUI가 뜨면 'Accept' 클릭하세요."
    } else {
        Write-Warn2 "Docker Desktop 실행파일을 찾지 못함: $dockerExe"
    }
} else {
    Write-Ok "이미 실행 중"
}

# ─── [7] Docker daemon 응답 대기 ────────────────────────────
Write-Step 7 "Docker daemon 응답 대기 (최대 90초)..."
$daemonOk = $false
for ($i = 1; $i -le 18; $i++) {
    try {
        $null = & docker.exe info 2>&1
        if ($LASTEXITCODE -eq 0) { $daemonOk = $true; break }
    } catch { }
    Start-Sleep -Seconds 5
}
if (-not $daemonOk) {
    Write-Fail "Daemon이 90초 내 응답 없음."
    Write-Host "         1) Docker Desktop GUI에서 라이선스 동의(Accept) 확인"
    Write-Host "         2) 그래도 'Engine starting'이면: Scripts\Setup\fix_docker_engine.bat"
    Stop-WithCode 20
}
Write-Ok "Daemon 응답"

# ─── [8] hello-world 검증 ───────────────────────────────────
Write-Step 8 "hello-world 검증..."
try {
    $null = & docker.exe run --rm hello-world 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "hello-world 성공"
    } else {
        Write-Warn2 "hello-world 실행 실패 (exit $LASTEXITCODE). 인터넷/Docker Hub 점검 필요."
    }
} catch {
    Write-Warn2 "hello-world 실행 중 예외: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  [DONE] Docker 환경 셋업 완료."                              -ForegroundColor Green
Write-Host ""
Write-Host "  다음 단계:"
Write-Host "    Scripts\Docker\Linux\Debug\debug_build.bat    (Linux 풀빌드)"
Write-Host "    Scripts\Docker\Windows\Debug\debug_build.bat  (Windows 풀빌드)"
Write-Host "============================================================" -ForegroundColor Green
Stop-WithCode 0
