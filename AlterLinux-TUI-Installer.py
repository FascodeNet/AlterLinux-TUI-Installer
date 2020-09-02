#!/usr/bin/env python
import locale
from dialog import Dialog

def main():
    main_dialog = Dialog(dialog="dialog")
    main_dialog.setBackgroundTitle("TDN is homo")
    if main_dialog.yesno("TDN is homo?") == main_dialog.OK:
        main_dialog.msgbox("sex TDN")
        
    print("TDN")
main()