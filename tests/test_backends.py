#!/usr/bin/env python3
"""Testes sem comandos privilegiados; pacman/apt/sudo são substituídos por stubs."""
import os
import subprocess
import tempfile
import pathlib
import shutil
import json

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'atualizador-ubuntu-debian-arch.sh'

def run(args, env=None, timeout=30):
    return subprocess.run(args, text=True, capture_output=True, env=env, timeout=timeout)

def check(b, msg):
    if not b: raise AssertionError(msg)

with tempfile.TemporaryDirectory(prefix='atualizar-32-test-') as d:
    base = pathlib.Path(d)
    # Apenas cópia TEMPORÁRIA; nunca modifica /etc/os-release real.
    mocked = base / 'atualizador-ubuntu-debian-arch.sh'
    fixture = base / 'os-release'
    fixture.write_text('ID=arch\nPRETTY_NAME="Arch Linux"\n')
    mocked.write_text(SCRIPT.read_text().replace('/etc/os-release', str(fixture)))
    shutil.copytree(ROOT / 'lib', base / 'lib')
    fake = base / 'fakebin'
    fake.mkdir()
    log = base / 'calls.log'
    (fake / 'pacman').write_text('''#!/usr/bin/env bash
printf 'pacman %s\\n' "$*" >> "$AT32_CALLS"
case "$1" in
  -Dk) echo 'no missing dependencies';;
  -Q) case "${2:-}" in -dt|-dtq) ;; -m) echo 'aur-helper 1.0';; *) echo 'linux 6.18'; echo 'linux-firmware 1.0';; esac;;
  -Qu) echo 'linux 6.18 -> 6.19';;
  *) echo "UNEXPECTED pacman option: $*" >&2; exit 9;;
esac
''')
    (fake / 'checkupdates').write_text('#!/usr/bin/env bash\necho "linux 6.18 -> 6.19"\n')
    (fake / 'apt-get').write_text('#!/usr/bin/env bash\necho APT_MUST_NOT_RUN >&2\nexit 99\n')
    (fake / 'dpkg').write_text('#!/usr/bin/env bash\necho DPKG_MUST_NOT_RUN >&2\nexit 99\n')
    for file in fake.iterdir(): file.chmod(0o755)
    home = base/'home'; home.mkdir()
    env = os.environ | {'HOME':str(home),'PATH':str(fake)+':'+os.environ['PATH'],'AT32_CALLS':str(log)}
    # O script rejeita execução como root; testes rodam como nobody em um HOME temporário.
    if os.geteuid()==0:
        import pwd
        u=pwd.getpwnam('nobody')
        for path in [base, home, fake, log.parent, base/'lib', base/'lib'/'atualizar']:
            os.chown(path, u.pw_uid, u.pw_gid)
        def invoke(cmd): return run(['runuser','-u','nobody','--','env',*[f'{k}={v}' for k,v in env.items()],*cmd],timeout=40)
    else:
        def invoke(cmd): return run(cmd,env,timeout=40)
    for args, keyword in [(['--distro'], 'Arch Linux | backend: pacman'),(['--simular','--sem-sudo'],'checkupdates'),(['--kernel','--sem-sudo'],'Arch — kernels'),(['--seguranca','--sem-sudo'],'Pacman — informações')]:
        r = invoke(['bash',str(mocked)]+args)
        check(r.returncode==0, f'{args} exit={r.returncode} stderr={r.stderr[-700:]}')
        check(keyword in r.stdout, f'{args} absent {keyword}')
        check('APT_MUST_NOT_RUN' not in r.stdout+r.stderr and 'DPKG_MUST_NOT_RUN' not in r.stdout+r.stderr, 'cross-backend apt/dpkg call')
    check(log.exists(), 'pacman not called')
    text = log.read_text()
    check('pacman -Dk' in text and 'pacman -Q' in text, 'pacman checks not called')
    check('pacman -Sy' not in text and 'pacman -Syu' not in text, 'unexpected package modification in read-only modes')
    reports = list((home/'Downloads'/'Relatorios-atualizar').glob('*.json'))
    check(len(reports)>=3, 'json not produced')
    check(all(json.loads(p.read_text())['metricas']['distro_id']=='arch' for p in reports), 'wrong backend marker')
    # Arch update: allowed ONLY if confirmed, no partial synchronization or AUR helper.
    unit = base/'unit.sh'
    unit.write_text(f'''#!/usr/bin/env bash
set -u
DISTRO_ID=arch
interrompido=0
parcial=0
falhou=0
secao() {{ :; }}
aviso() {{ :; }}
pular() {{ :; }}
achado() {{ :; }}
existe() {{ command -v "$1" >/dev/null; }}
confirmar() {{ return 0; }}
etapa() {{ shift; "$@"; }}
source '{ROOT}/lib/atualizar/arch.sh'
pkg_atualizar
''')
    (fake/'sudo').write_text('#!/usr/bin/env bash\nprintf "sudo %s\\n" "$*" >> "$AT32_CALLS"\nexit 0\n')
    (fake/'sudo').chmod(0o755)
    r=invoke(['bash',str(unit)])
    check(r.returncode==0, f'arch update unit failed {r.stderr}')
    check(log.read_text().count('sudo pacman -Syu')==1, 'not one full Arch transaction')
    check('sudo pacman -Sy\n' not in log.read_text(), 'partial upgrade attempted')
    # Ubuntu: deve carregar somente APT (sem chamar pacman), em fixture não privilegiada.
    (fake/'apt-get').unlink()
    (fake/'dpkg').unlink()
    fixture.write_text('ID=ubuntu\nPRETTY_NAME="Ubuntu Test Fixture"\n')
    before = log.read_text()
    r = invoke(['bash', str(mocked), '--distro'])
    check(r.returncode==0 and 'Ubuntu | backend: APT' in r.stdout, 'Ubuntu dispatch')
    r = invoke(['bash', str(mocked), '--simular', '--sem-sudo'])
    check(r.returncode==0, f'Ubuntu mocked distro apt-simulated: {r.stderr[-600:]}')
    check(before == log.read_text(), 'pacman called by Ubuntu backend')
    print('OK: Debian live (tested separately), Arch isolated, Ubuntu simulated, JSON, mocked full upgrade, no partial sync')
