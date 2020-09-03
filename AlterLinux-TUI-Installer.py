#!/usr/bin/env python
import locale
import subprocess
from subprocess import DEVNULL
from dialog import Dialog
import re
hdds_re = re.compile(r"^/dev/[hsnm][dmv].[1234567890eb].*$")


def finish():
    subprocess.call("clear")
    exit(0)

def ask_sure_to_exit(main_dialog):
    if main_dialog.yesno("Are you sure to exit?") == main_dialog.OK:
        finish()

def was_input_success(main_dialog, input_str):
    if input_str[0] == "cancel":
        ask_sure_to_exit(main_dialog)
        return False
    if input_str[1] == "":
        return False
    return True

def input_dialog(main_dialog, txt):
    while (True):
        result = main_dialog.inputbox(txt, width=50)
        if was_input_success(main_dialog, result) == False:
            continue
        return result[1]

def password_dialog(main_dialog, txt):
    while (True):
        result = main_dialog.passwordbox(txt, width=50, insecure=True)
        if was_input_success(main_dialog, result) == False:
            continue
        while(True):
            re_result = main_dialog.passwordbox("Enter the same password again.",
            width=40, insecure=True)
            if was_input_success(main_dialog, re_result) == False:
                continue
            else:
                break
        if result[1] != re_result[1]:
            main_dialog.msgbox("Error\n\nPassword doesn't match")
            continue

        return result[1]

# Keyboard layout
def get_key_layouts():
    resultkun = subprocess.check_output("localectl list-keymaps", stdin=DEVNULL, stderr=DEVNULL,shell=True)
    reskun    = resultkun.decode()
    str_lskun = []
    for strkun in reskun.split("\n"):
        str_lskun.append(strkun)
    return str_lskun

def key_layout_select(main_dialog):
    key_layouts_str  = get_key_layouts()
    key_layouts_menu = []
    for layouts_s in key_layouts_str:
        key_layouts_menu.append((layouts_s,""))
    while(True):
        code,tag = main_dialog.menu("Select your keyboard layout.",
        choices  = key_layouts_menu)
        if code == main_dialog.OK:
            if main_dialog.yesno("Is \"{}\" correct?".format(tag)) == main_dialog.OK:
                return tag
            else:
                continue
            return tag
        else:
            ask_sure_to_exit(main_dialog)
            continue

# HDD
def get_editable_disk():
    tmp           = subprocess.check_output("lsblk -dpln -o NAME", stdin=DEVNULL, stderr=DEVNULL, shell=True)
    disk_list     = tmp.decode()
    str_disk_list = disk_list.split("\n")
    return str_disk_list

def target_diskedit_select(main_dialog):
    editable_disk_str = get_editable_disk()
    editable_disk = []
    for disk in editable_disk_str:
        editable_disk.append((disk, ""))
    code,tag = main_dialog.menu("Which disk do you want to edit?",
    choices=editable_disk)
    if code == main_dialog.OK:
        subprocess.call(("sudo","cfdisk",tag))#.format(tag))

def get_target_partition():
    resultkun    = subprocess.check_output("lsblk -pln -o NAME", stdin=DEVNULL, stderr=DEVNULL,shell=True)
    reskun       = resultkun.decode()
    str_listkun  = []
    str_listkun.append("Edit the partitions manually")
    for strkun in reskun.split("\n"):
        matchkun = hdds_re.match(strkun)
        if not matchkun is None:
            str_listkun.append(matchkun.group())
    return str_listkun

def hdd_select(main_dialog):
    can_install_partition_str = get_target_partition()
    can_install_partitions    = []
    for insthdd in can_install_partition_str:
        can_install_partitions.append((insthdd,""))
    while(True):
        code,tag = main_dialog.menu("Which HDD do you want to install?",
        choices  = can_install_partitions)
        if code == main_dialog.OK:
            if tag == "Edit the partitions manually":
                target_diskedit_select(main_dialog)
                continue
            if main_dialog.yesno("Do you want to install in \"{}\" ?".format(tag)) == main_dialog.OK:
                return tag
            else:
                continue
        else:
            ask_sure_to_exit(main_dialog)
            continue

# main
def main():
    main_dialog = Dialog(dialog="dialog")
    main_dialog.setBackgroundTitle("Alter Linux Installer")
    if main_dialog.yesno("Install Alter Linux?") == main_dialog.OK:
        conf_str     = "Start the installation with the following settings.\nAre you sure?\n\n"
        # get keyboard layout
        key_layout   = key_layout_select(main_dialog)
        conf_str    += "Keyboard layout : {}\n".format(key_layout)
        # get install target hdd
        hdd_target   = hdd_select(main_dialog)
        conf_str    += "Install target partition : {}\n".format(hdd_target)
        # set user data
        user_name    = input_dialog(main_dialog, "What is your user name?",)
        conf_str    += "User name : {}\n".format(user_name)
        # set host name
        host_name    = input_dialog(main_dialog, "What is the name of this computer?")
        conf_str    += "Host name : {}\n".format(host_name)
        # password
        user_pass    = password_dialog(main_dialog, "Type a safely password.",)
        root_pass    = password_dialog(main_dialog, "Type a safely password for administrator account.")
        # Confirmation
        while(True):
            if main_dialog.yesno(conf_str,height=15,width=50) == main_dialog.OK:
                pass
            else:
                ask_sure_to_exit(main_dialog)
                continue
        finish()
    else:
        finish()


main()