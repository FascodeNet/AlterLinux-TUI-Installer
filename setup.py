from setuptools import setup
setup(
    name="alterlinux_tui_installer",
    version="0.0.0.1",
    description="setup alterlinux with tui",
    author="FascodeNetwork",
    install_requires=["pythondialog"],
    entry_points={
        "console_scripts":[
            "alterlinux_tui_installer=alterlinux_tui_installer.AlterLinux_TUI_Installer:main"
        ]
    }
)