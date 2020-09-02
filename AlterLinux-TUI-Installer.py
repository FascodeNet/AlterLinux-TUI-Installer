#!/usr/bin/env python
import locale
import subprocess
from subprocess import DEVNULL
from dialog import Dialog
import re
hdds_re=re.compile(r"^/dev/[hsn][dv].[1234567890e].*$")
def get_hdds():

    resultkun=subprocess.check_output("lsblk -pln -o NAME",stdin=DEVNULL,stderr=DEVNULL,shell=True)
    reskun= resultkun.decode()
    str_listkun=[]
    for strkun in reskun.split("\n"):
        matchkun=hdds_re.match(strkun)
        if not matchkun is None:
            str_listkun.append(matchkun.group())
    return str_listkun

def hdd_select(main_dialog):
    can_install_hdds_Str=get_hdds()
    can_installhdds=[]
    for insthdd in can_install_hdds_Str:
        can_installhdds.append((insthdd,""))
    code,tag=main_dialog.menu("Which HDD do you install?",
    choices=can_installhdds)
    if code == main_dialog.OK:
        print(tag)
        pass

def main():
    main_dialog = Dialog(dialog="dialog")
    main_dialog.setBackgroundTitle("Alter Linux Installer")
    if main_dialog.yesno("Install Alter Linux?") == main_dialog.OK:
        hdd_select(main_dialog)
    else:
        pass
main()