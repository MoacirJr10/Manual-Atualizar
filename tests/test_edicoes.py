#!/usr/bin/env python3
"""Testes não destrutivos de identidade e isolamento; nunca chama gerenciadores reais."""
import os, pathlib, shutil, subprocess, tempfile, pwd

ROOT=pathlib.Path(__file__).resolve().parents[1]
DISTROS={'ubuntu':('Ubuntu','APT'),'debian':('Debian','APT'),'arch':('Arch Linux','pacman')}

def must(flag,msg):
    if not flag: raise AssertionError(msg)

with tempfile.TemporaryDirectory(prefix='edicoes-') as td:
    base=pathlib.Path(td)
    fake=base/'fakebin'; fake.mkdir()
    home=base/'home'; home.mkdir()
    # Marcadores: comandos reais proibidos; todos os managers são stubs de teste.
    commands={
      'pacman': '''#!/usr/bin/env bash
printf 'pacman %s\\n' "$*" >> "$TEST_CALLS"
case "$1" in -Dk|-Q|-Qu) case "$1:$2" in -Q:) printf 'linux 6.19\\nlinux-firmware 1.0\\n';; esac;; *) exit 77;; esac
''',
      'checkupdates': '#!/usr/bin/env bash\necho "linux 6.19 -> 6.20"\n',
      'apt-get': '''#!/usr/bin/env bash
printf 'apt-get %s\\n' "$*" >> "$TEST_CALLS"
case "$*" in *-s*) exit 0;; *) exit 76;; esac
''',
      'dpkg': '''#!/usr/bin/env bash
printf 'dpkg %s\\n' "$*" >> "$TEST_CALLS"
case "$1" in --audit) exit 0;; *) exit 74;; esac
''',
      'dpkg-query': '''#!/usr/bin/env bash
printf 'dpkg-query %s\\n' "$*" >> "$TEST_CALLS"
printf 'installed\\tfake:amd64\\t1.0\\n'
''',
      'apt-mark': '#!/usr/bin/env bash\nexit 0\n',
      'apt': '#!/usr/bin/env bash\nexit 0\n',
      'apt-cache': '#!/usr/bin/env bash\nexit 0\n',
      'sudo': '#!/usr/bin/env bash\necho SUDO_NOT_ALLOWED >&2\nexit 88\n',
    }
    for name,src in commands.items():
        p=fake/name;p.write_text(src);p.chmod(0o755)
    log=base/'commands.log';log.touch()
    as_root=os.geteuid()==0
    if as_root:
        u=pwd.getpwnam('nobody')
        for p in (base,fake,home,log): os.chown(p,u.pw_uid,u.pw_gid)
    env=os.environ.copy()
    env.update(HOME=str(home),PATH=str(fake)+':'+env['PATH'],TEST_CALLS=str(log))
    def invoke(script,*args,timeout=90):
        cmd=['bash',str(script),*args]
        if as_root: cmd=['runuser','-u','nobody','--','env',*[f'{k}={v}' for k,v in env.items()],*cmd]
        return subprocess.run(cmd,text=True,capture_output=True,env=env,timeout=timeout)
    for distro,(name,pkg) in DISTROS.items():
        original=ROOT/'edicoes'/distro/f'atualizador-{distro}.sh'
        source=original.read_text()
        must(subprocess.run(['bash','-n',str(original)]).returncode==0,distro+' bash -n')
        fixture=base/f'os-release-{distro}'
        fixture.write_text(f'ID={distro}\\nPRETTY_NAME="{name} TEST"\\n'.replace('\\n','\n'))
        copy=base/f'atualizador-{distro}.sh'
        copy.write_text(source.replace('/etc/os-release',str(fixture)))
        out=invoke(copy,'--distro')
        must(out.returncode==0 and f'{name} | backend: {pkg}' in out.stdout,f'{distro} --distro: {out.returncode} {out.stderr}')
        out=invoke(copy,'--versao')
        must(out.returncode==0 and f'3.2-preview ({distro})' in out.stdout,distro+' --versao')
        fixture.write_text('ID=other\n')
        log.write_text('')
        out=invoke(copy,'--distro')
        must(out.returncode==2,distro+' did not reject wrong OS')
        must(log.read_text()=='',distro+' wrong OS ran package command')
        fixture.write_text(f'ID={distro}\nPRETTY_NAME="{name} TEST"\n')
        log.write_text('')
        out=invoke(copy,'--simular','--sem-sudo',timeout=120)
        must(out.returncode==0,f'{distro} --simular status {out.returncode}: {out.stderr[-500:]} {out.stdout[-500:]}')
        commands_run=log.read_text()
        must('SUDO_NOT_ALLOWED' not in out.stdout+out.stderr,distro+' sudo used')
        if distro=='arch':
            must('apt-get ' not in commands_run and 'dpkg ' not in commands_run,'Arch called APT')
            must('pacman -Syu' not in commands_run and 'pacman -Sy' not in commands_run,'Arch modified DB during simulation')
            must('pacman -Dk' in commands_run,'Arch pacman not checked')
        else:
            must('pacman ' not in commands_run,distro+' called pacman')
            must('apt-get ' in commands_run,distro+' APT not checked')
        expected=home/'Downloads'/f'Relatorios-atualizador-{distro}'
        must(list(expected.glob('*.json')),distro+' reports missing')
        print('PASS',distro,': identificação, rejeição da outra distro, simulação sem sudo, relatórios')
print('PASS: isolamento e testes não destrutivos concluídos')
