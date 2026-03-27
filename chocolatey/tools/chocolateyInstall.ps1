$toolsDir = Split-Path -parent $MyInvocation.MyCommand.Definition
Install-BinFile -Name 'kemforge' -Path "$toolsDir\kemforge.exe"

