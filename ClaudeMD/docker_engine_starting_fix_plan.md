# Docker Desktop "Engine Starting" 무한 대기 진단·해결 계획서

작성일: 2026-05-07
대상 프로젝트: `C:\Users\user\Desktop\linux_shared_folder\ServerCore`

---

## 1. 목표

> **"Docker Desktop을 켰는데 좌하단이 'Engine starting…'에서 영원히 멈춰있는 상태"를 자동으로 진단하고, 안전한 fix를 자동 시도하며, 사용자 개입이 필요한 부분만 명확히 안내하는 .bat 작성**

- 사용자는 `fix_docker_engine.bat` 더블클릭만 하면 됨
- 스크립트 끝나는 시점에 `docker info` 가 응답 = Engine 정상 기동
- 자동 fix가 실패하면 다음 시도할 사용자 액션을 정확히 안내

---

## 2. 증상 정의

| 증상 | 어떻게 보이는가 |
|------|----------------|
| Engine starting 무한 대기 | Docker Desktop GUI 좌하단에 회색/주황 점 + "Engine starting..." 텍스트가 5분 이상 유지 |
| docker CLI 미응답 | `docker info` → `error during connect: ... open //./pipe/dockerDesktopLinuxEngine: The system cannot find the file specified.` |
| Whale 아이콘 회색 | 트레이의 고래가 회색이고 깜박이지 않음 (또는 영원히 깜박임) |

> 위와 다른 증상(예: GUI 자체가 안 뜸, "Docker Desktop is unable to detect a Hyper-V")은 별도 케이스 → 이 문서 범위 밖.

---

## 3. 발생 원인 (카테고리별)

### 3.1 WSL2 백엔드 문제 (가장 흔함)

| 원인 | 진단 명령 | 자동 fix 가능? |
|------|----------|----------------|
| WSL kernel이 너무 오래됨 | `wsl --status` (WSL Version 표시) | ✅ `wsl --update` |
| 기본 WSL 버전이 1로 설정 | `wsl --status` | ✅ `wsl --set-default-version 2` |
| `docker-desktop` distro가 stopped/broken | `wsl -l -v` | ✅ `wsl --shutdown` 후 Docker Desktop 재시작 |
| `docker-desktop-data` distro 손상 | `wsl -l -v` 에서 `Stopped` + 시작 시 에러 | ⚠️ `wsl --unregister docker-desktop-data` (데이터 손실 → 사용자 확인) |
| WSL 자체가 미설치 | `wsl --status` 에러 | ✅ `wsl --install --no-distribution` (단 재부팅 필요) |

### 3.2 가상화 / Hyper-V

| 원인 | 진단 | 자동 fix? |
|------|------|-----------|
| BIOS에서 VT-x/AMD-V 비활성 | `systeminfo \| findstr "Virtualization"` | ❌ BIOS 진입 안내 |
| Windows의 Hyper-V/VirtualMachinePlatform feature 비활성 | `Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform` | ✅ `dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart` (재부팅 필요) |
| VMware/VirtualBox와 충돌 | `tasklist` 에서 vmware-vmx.exe / VBoxHeadless.exe 감지 | ⚠️ 안내만 (Hypervisor 충돌 — 사용자가 결정) |
| Windows 11 Memory Integrity (Core Isolation) | PowerShell `Get-CimInstance ... HypervisorEnforcedCodeIntegrity` | ❌ 사용자에게 Windows Security GUI 안내 |

### 3.3 Docker Desktop 자체 상태 손상

| 원인 | 진단 | 자동 fix? |
|------|------|-----------|
| `%APPDATA%\Docker\settings.json` 깨짐 | json parse 시도 | ✅ 백업 후 삭제 → Docker Desktop이 default 재생성 |
| `%LOCALAPPDATA%\Docker\log.txt` 마지막 줄에 panic/fatal | grep | 진단용 (자동 fix는 cause 별로) |
| 부분 업데이트 후 일관성 깨짐 | `docker --version` vs Docker Desktop 버전 mismatch | ⚠️ 재설치 안내 |
| Docker Desktop 백그라운드 프로세스 좀비 | `tasklist \| findstr Docker` 다중 인스턴스 | ✅ 모두 kill 후 단일 시작 |

### 3.4 네트워크 / 보안

| 원인 | 진단 | 자동 fix? |
|------|------|-----------|
| 회사 VPN/프록시가 Docker Hub 차단 | `curl https://registry-1.docker.io/v2/` | ❌ IT/네트워크 안내 |
| 방화벽이 `com.docker.backend.exe` 차단 | Windows Defender Firewall 규칙 | ⚠️ 규칙 추가는 가능하나 보안 영향 큼 → 안내 |
| 안티바이러스가 Docker 프로세스 quarantine | AV 로그 (제품별) | ❌ AV 예외 등록 안내 |

### 3.5 시스템 리소스

| 원인 | 진단 | 자동 fix? |
|------|------|-----------|
| C: 드라이브 공간 부족 (WSL VHD 자랄 공간 < 10GB) | `Get-PSDrive C` | ⚠️ 부족 시 경고 + 캐시 정리 안내 |
| RAM 부족 (가용 < 2GB) | `Get-CimInstance Win32_OperatingSystem` | 안내만 |

### 3.6 권한

| 원인 | 진단 | 자동 fix? |
|------|------|-----------|
| 사용자가 `docker-users` 그룹 미가입 | `net localgroup docker-users` | ✅ `net localgroup docker-users %USERNAME% /add` (관리자 권한 필요, 재로그인 필요) |
| 관리자 계정으로 설치, 일반 계정으로 실행 | 위와 동상 | ✅ 동상 |

---

## 4. 자동 진단·해결 우선순위

> **안전한 것부터 → 데이터 영향이 큰 것까지 단계별로 시도. 각 단계 후 `docker info` 폴링 → 성공 시 종료.**

```
[L1] 가장 안전 — 재시작만
    ├─ Docker Desktop GUI 종료
    ├─ 모든 Docker 관련 프로세스 kill
    │     "Docker Desktop.exe", "com.docker.backend.exe", "com.docker.build.exe"
    ├─ wsl --shutdown
    ├─ Docker Desktop 다시 시작
    └─ 60초 polling → 성공 시 종료

[L2] WSL 갱신
    ├─ wsl --update
    ├─ wsl --set-default-version 2
    ├─ wsl --shutdown
    ├─ Docker Desktop 재시작
    └─ 60초 polling → 성공 시 종료

[L3] Docker Desktop 설정 reset (데이터 보존)
    ├─ Docker Desktop 종료
    ├─ %APPDATA%\Docker\settings.json 백업 (settings.json.bak.<timestamp>)
    ├─ settings.json 삭제 (Docker Desktop이 default로 재생성)
    ├─ Docker Desktop 재시작
    └─ 90초 polling → 성공 시 종료

[L4] WSL distro 재등록 (이미지 캐시 삭제됨, 사용자 확인 필요)
    ├─ 사용자에게 "docker-desktop-data 등록 해제 시 모든 컨테이너/이미지 삭제됨. 진행? (y/N)"
    │     → N이면 [L5]로
    ├─ Docker Desktop 종료
    ├─ wsl --unregister docker-desktop
    ├─ wsl --unregister docker-desktop-data
    ├─ Docker Desktop 재시작 (자체적으로 두 distro 재생성)
    └─ 120초 polling → 성공 시 종료

[L5] 진단 정보 수집 + 사용자 안내
    ├─ %LOCALAPPDATA%\Docker\log.txt 마지막 200줄 → %TEMP%\docker_diag_<ts>.log
    ├─ wsl --status, wsl -l -v 결과
    ├─ systeminfo 가상화 항목
    ├─ docker-users 그룹 멤버십
    ├─ C: 디스크 공간
    ├─ Hyper-V/VirtualMachinePlatform feature 상태
    ├─ Docker Desktop 버전
    └─ 화면에 진단 요약 + log 파일 경로 출력
        + 다음 시도할 액션 안내:
            * 가상화 OFF → BIOS 진입
            * Hyper-V feature 비활성 → dism 명령 안내
            * AV 의심 → AV 예외 등록 안내
            * Factory reset 안내 (Docker Desktop 메뉴 > Troubleshoot > Reset to factory defaults)
            * 최후: Docker Desktop 완전 제거 후 재설치
```

---

## 5. 스크립트 명세

### 5.1 파일 위치 / 이름

`Scripts\Setup\fix_docker_engine.bat`

> `setup_docker_windows.bat`(설치)와 분리. 이쪽은 **이미 설치된 환경의 복구**용.

### 5.2 인자

```
fix_docker_engine.bat [--level N] [--diag-only] [--yes]
```

- `--level N`: 1..5 중 어느 단계까지만 시도할지 (기본: 3)
  - L4 (distro 재등록)는 데이터 영향 있어 명시적으로 `--level 4` 필요
- `--diag-only`: fix 시도 없이 진단 정보만 수집 (L5만 실행)
- `--yes`: 모든 confirm prompt에 자동 동의 (CI 환경)

### 5.3 종료 코드

| exit | 의미 |
|------|------|
| 0    | docker info 정상 응답 → Engine 정상 기동 확인 |
| 1    | 일반 에러 |
| 2    | BIOS 가상화 비활성 — 사용자 BIOS 진입 필요 |
| 3    | Windows feature 비활성 — 재부팅 필요 |
| 4    | 모든 자동 단계 시도 후도 daemon 미응답 — 진단 로그 보고 |
| 5    | 사용자가 confirm prompt에 No 응답 — 중단 |

### 5.4 출력 형식

각 단계마다:
```
[L1] Restart only
  → Killing Docker processes ...           OK
  → wsl --shutdown ...                     OK
  → Starting Docker Desktop ...            OK
  → Polling docker info (60s) ...          STILL DOWN
[L2] WSL update
  → wsl --update ...                       OK
  ...
[SUCCESS] Docker daemon is responding (took 73s, fixed at L2).
```

실패 시:
```
[FAILED] Docker daemon still not responding after L1..L3.
Diagnostic log: %TEMP%\docker_diag_20260507_153012.log

Next actions to try:
  1. BIOS virtualization seems OFF — enter BIOS and enable Intel VT-x / AMD-V.
  2. Antivirus may be blocking Docker — check Sophos/Norton/etc. exception list.
  3. Last resort: Docker Desktop GUI > Troubleshoot > Reset to factory defaults.
```

### 5.5 멱등성

- 모든 단계가 "이미 정상이면 skip"
- L1 첫 polling 전에 한 번 docker info 시도 → 이미 응답하면 즉시 [SUCCESS] (0초 종료)

---

## 6. 사용자 시나리오

### 6.1 가장 흔한 케이스 — WSL 갱신만으로 해결

```
1. Docker Desktop 켰는데 Engine starting 무한
2. fix_docker_engine.bat 더블클릭
3. [L1] 재시작 시도 → 실패
4. [L2] wsl --update → docker info 응답 → [SUCCESS]
5. 빌드 진행
```

### 6.2 설정 손상 케이스

```
1. fix_docker_engine.bat
2. [L1] 실패
3. [L2] 실패
4. [L3] settings.json 백업 후 삭제 → 응답 → [SUCCESS]
```

### 6.3 BIOS 가상화 OFF

```
1. fix_docker_engine.bat
2. [L1..L3] 모두 실패
3. [L5] 진단 → "Virtualization Enabled In Firmware: No" 발견
4. 사용자에게 BIOS 활성화 안내 + exit 2
5. 사용자가 BIOS 진입 후 재시작 → 자동 해결
```

### 6.4 진단만 수행

```
> fix_docker_engine.bat --diag-only
[DIAG] Collecting Docker / WSL / system state ...
Saved: %TEMP%\docker_diag_20260507_153012.log
```

---

## 7. 자동화 가능 vs 사용자 액션 정리

| 항목 | 자동화? | 비고 |
|------|---------|------|
| Docker 프로세스 재시작 | ✅ | L1 |
| `wsl --shutdown` | ✅ | L1 |
| `wsl --update` | ✅ | L2 |
| `wsl --set-default-version 2` | ✅ | L2 |
| settings.json reset | ✅ | L3 (백업 후) |
| WSL distro 재등록 | ⚠️ | L4 (사용자 confirm 필수) |
| `docker-users` 그룹 추가 | ✅ | 관리자 권한 필요, 재로그인 필요 |
| Windows feature 활성화 | ✅ | dism, 재부팅 필요 |
| 진단 로그 수집 | ✅ | L5 |
| BIOS 가상화 활성화 | ❌ | 안내만 |
| Memory Integrity 비활성화 | ❌ | Windows Security GUI 안내 |
| 안티바이러스 예외 등록 | ❌ | 제품별 GUI 안내 |
| 회사 프록시 우회 | ❌ | IT 부서 안내 |
| Factory reset | ❌ | Docker Desktop GUI 메뉴 안내 |
| 완전 재설치 | ⚠️ | `setup_docker_windows.bat` 호출로 자동화 가능 |

---

## 8. 실패 모드 / 사전 점검

| 위험 | 완화책 |
|------|--------|
| `wsl --update` 자체가 실패 (네트워크 차단) | 에러 메시지 + 수동 다운로드 링크 안내 |
| Docker 프로세스 kill 중 사용자가 다른 컨테이너 작업 중 | L1 시작 전 "실행 중인 컨테이너가 있다면 중단됩니다. 진행? (y/N)" |
| 관리자 권한 없이 더블클릭 | 자체 UAC 승격 (PowerShell `Start-Process -Verb RunAs`) |
| L4 (distro 재등록) 후 사용자 컨테이너 모두 삭제 | 명시적 confirm + `--level 4` 인자 강제 |
| settings.json 백업이 호환 안 되는 새 버전 Docker Desktop | 백업이라 영향 없음 (사용자가 수동 복구 가능) |
| `docker info` polling이 실제 일시적 응답 후 끊기는 케이스 | 3회 연속 성공 시에만 [SUCCESS] 처리 |
| 한글 Windows 환경에서 `findstr` 출력 인코딩 | `chcp 65001` 강제 + 영문 키워드만 매칭 |
| L1에서 com.docker.* 프로세스가 service로 등록되어 있어 kill 해도 다시 살아남 | `Stop-Service com.docker.service` 후 kill |

---

## 9. 단계별 도입 로드맵

### PHASE 0 — 디렉터리 / 위치 결정

1. `Scripts\Setup\` 디렉터리에 함께 위치 (이미 `setup_docker_windows.bat` 계획 있음)
2. README의 "사전 준비" 섹션에 트러블슈팅 한 줄 안내 추가
   (예: "Engine이 안 뜨면 `Scripts\Setup\fix_docker_engine.bat` 실행")

### PHASE 1 — 핵심 .bat 작성

1. `Scripts\Setup\fix_docker_engine.bat` 작성 (4번의 L1..L5 동작 그대로)
2. 한 docker info polling 헬퍼 함수
3. 종료 코드별 안내 메시지
4. 멱등성 테스트 (정상 상태 PC에서 실행 → 0초 [SUCCESS])

**검증 기준 (PHASE 1 완료 조건)**:
- 정상 상태 PC: 0초 만에 [SUCCESS]
- WSL 미갱신 상태 시뮬레이션: L2에서 [SUCCESS]
- settings.json 손상 시뮬레이션 (`echo "{ broken" > settings.json`): L3에서 [SUCCESS]
- 가상화 OFF 시뮬레이션: L5에서 정확한 안내 + exit 2

---

## 10. 신규 / 변경 파일 요약

| 파일 | 역할 |
|------|------|
| `Scripts/Setup/fix_docker_engine.bat` | Docker Desktop "Engine starting" 무한 대기 진단·해결 (이 계획의 결과물) |
| `README.md` | "사전 준비" 또는 "트러블슈팅" 섹션에 한 줄 추가 |
| `ClaudeMD/docker_engine_starting_fix_plan.md` | 이 문서 |

---

## 11. 한 줄 요약

`Scripts\Setup\fix_docker_engine.bat` 한 번 실행으로,
**프로세스 재시작 → WSL 갱신 → 설정 reset** 까지 안전한 자동 fix를 순차 시도하고,
실패 시 진단 로그 수집 + 정확한 사용자 액션(BIOS, AV, Factory reset 등) 안내로 끊김 없이 가이드한다.
