from setuptools import setup,find_packages
setup(
    name="alterlinux_tui_installer",
    version="0.0.0.1",
    description="setup alterlinux with tui",
    author="FascodeNetwork",
    install_requires=["pythondialog"],
    packages=find_packages(),
    entry_points={
        "console_scripts":[
            "alterlinux_tui_installer=alterlinux_tui_installer.alterlinux_tui_installer:main"
        ]
    }
)