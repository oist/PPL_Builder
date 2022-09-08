# PPL-Builder
Tool for building LabVIEW Packed Project Library files on Windows and cRIO-9045.

This tool can be used with [G-CLI](https://github.com/JamesMc86/G-CLI) and expects the following arguments:

- Path to the lvlib file, relative to the directory in which g-cli is executed
- Relative path to the directory in which the PPL should be stored when built
- Debug? A 0 or 1 (actually, this checks != 0) determining if debugging should be enabled for the PPL
- Target: "Windows" or "cRIO", in this repository, for a Windows desktop PPL or a cRIO-9045 PPL
- BuildType: "MAJOR", "MINOR", "PATCH" or "BUILD", determining which values should be incremented in the version number. See the VIs under `Support > Version Parsing` and `Support > Version Scripting` for more detail.
- A list of PPL dependencies, used in the generation of the NIPKG file `Depends:` entry.

An example call would be:
```
# You can use / or \ in the arguments passed to LabVIEW, but not '/' in the path for the VI.
# Use "" to enclose arguments with spaces in the path or filename
> g-cli --lv-ver 2019 --verbose PPL_Builder\Call_Builder_Wiresmith.vi -- "Source directory\source library.lvlib" PPLs/Current 1 Windows MAJOR "SomeOtherLibrary.lvlibp" "SomeThirdLibrary.lvlibp"
```

This tool also stores information about the author and company in the PPL file - these values can be specified in
[builder-config.ini](./builder-config.ini), which is in the format read by the LabVIEW Config INI file VIs.


## Adding a new target
Other targets could be added by extending the enum entries (`TargetType.ctl`),
adding a string matcher in `Parse CLI Inputs GoCD.vi` (to convert from the string argument to the enum),
and then appropriately configuring `Get Target Item` and `Init Build Spec.vi` with new cases in their case structures
(although Get Target Item might be able to reuse an existing case, depending on the Target),
providing an NI_PPL build specification via the Application Builder API.\
You should also add a new '`blankProject_<target>.lvproj`' file (`Open Project Copy.vi` loads a
project with the filename "blankProject_%s.lvproj" with the enum passed to Format to String).

## Project Conditional Disable Symbols
The code contained within the `PPL INI Parsing.lvlib` library reads a configuration file (`BuildConfig.ini`),
to be found alongside the library being built (the first argument to `Call_Builder_Wiresmith.vi`).

This file should take the format shown in [ExampleConfig.ini](./ExampleConfig.ini),
which demonstrates the definition of various "ProjectSymbols", both for all projects, and divided by 'Release' and 'Debug' builds.

The values parsed from this file are applied as Project Conditional Disable Symbols,
and can be used in the code being built to change its behaviour at compile-time.
