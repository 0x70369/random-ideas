1. [uindols updates in PowerShell](https://christitus.com/install-windows-update-powershell/)

2. [Install winget if not already present](https://christitus.com/installing-appx-without-msstore/) (can also be done with WinUtil)

3. [WinUtil](https://github.com/ChrisTitusTech/winutil)

4. [MAS](https://massgrave.dev/)

5. Create the "C:\tmp" folder and set up the `.bat` script inside the "Scripts" folder

6. Change the NTP server from time.windows.com to literally anything else (like pool.ntp.org)

7. [Driver Store Explorer](https://github.com/lostindark/driverstoreExplorer)

-------------------------------------------------------------------------------
[Winget](https://github.com/microsoft/winget-cli) packages from the M$ store

`winget install -e 9WZDNCRFJBMP --accept-source-agreements --accept-package-agreements` (Microsoft Store)

`winget install -e 9PG2DK419DRG 9N4D0MSMP0PT 9N5TDP8VCMHS 9PMMSR1CGPWG 9N95Q1ZZPMH4 9MVZQVXJBQ9V 9NCTDW2W1BH8 --accept-source-agreements --accept-package-agreements` (Media extentions)

`winget install -e 9MV0B5HZVK9Z 9MWPM2CQNLHN 9WZDNCRD1HKW 9NKNC0LD5NN6 9NZKPSTSNW4P --accept-source-agreements --accept-package-agreements` (Xbox and dependencies)

`winget install -e 9NQPSL29BFFF --accept-source-agreements --accept-package-agreements` (OpenCl/OpenGL/Vulkan compatibility pack)

`winget install -e 9NPV76S164X5 --accept-source-agreements --accept-package-agreements` (DirectX Runtime)

`winget install -e 9MZ95KL8MR0L --accept-source-agreements --accept-package-agreements` (Snipping Tool)