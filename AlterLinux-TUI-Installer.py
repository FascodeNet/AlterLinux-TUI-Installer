#!/usr/bin/env python
import locale
import subprocess
from subprocess import DEVNULL
from dialog import Dialog
import re
hdds_re=re.compile(r"^/dev/[hsnm][dmv].[1234567890eb].*$")
def get_hdds():

    resultkun=subprocess.check_output("lsblk -pln -o NAME",stdin=DEVNULL,stderr=DEVNULL,shell=True)
    reskun= resultkun.decode()
    str_listkun=[]
    for strkun in reskun.split("\n"):
        matchkun=hdds_re.match(strkun)
        if not matchkun is None:
            str_listkun.append(matchkun.group())
    return str_listkun
def get_key_layouts():
    resultkun=subprocess.check_output("localectl list-keymaps",stdin=DEVNULL,stderr=DEVNULL,shell=True)
    reskun= resultkun.decode()
    str_lskun=[]
    for strkun in reskun.split("\n"):
        str_lskun.append(strkun)
    return str_lskun
def key_layout_select(main_dialog):
    key_layouts_str=get_key_layouts()
    key_layouts_menu=[]
    for layouts_s in key_layouts_str:
        key_layouts_menu.append((layouts_s,""))
    while(True):
        code,tag=main_dialog.menu("Select your key layout"
        ,choices=key_layouts_menu)
        if code == main_dialog.OK:
            return tag
        else:
            continue
def hdd_select(main_dialog):
    can_install_hdds_Str=get_hdds()
    can_installhdds=[]
    for insthdd in can_install_hdds_Str:
        can_installhdds.append((insthdd,""))
    while(True):
        code,tag=main_dialog.menu("Which HDD do you install?",
        choices=can_installhdds)
        if code == main_dialog.OK:
            return tag
        else:
            continue
            

def main():
    main_dialog = Dialog(dialog="dialog")
    main_dialog.setBackgroundTitle("Alter Linux Installer")
    if main_dialog.yesno("Install Alter Linux?") == main_dialog.OK:
        #hdd_select(main_dialog)
        key_lay=key_layout_select(main_dialog)
        main_dialog.msgbox(key_lay)
        hdd_current=hdd_select(main_dialog)
        main_dialog.msgbox(hdd_current)
    else:
        pass
main()