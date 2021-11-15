# premake5-lib
Scripts for premake5 projects.

## ptran

Suppose you have a static library with some dependencies. 
```
project "lib_a"
    kind "StaticLib"
    links {"lib_b", "lib_c"}
```
Actually it's dependencies will not be linked with it, because static libraries archived by ar command. 
But any executable that use this library should manually link against library dependencies. 
```
project "exe"
    kind "ConsoleApp"
    links {"lib_a", "lib_b", "lib_c"}
```
This script allows you to automatically propagate such information from libraries to executables.
And instead of specifying full set of dependencies you just link against libraies in direct relation
to your project.
```
project "exe"
    kind "ConsoleApp"
    links {"lib_a"}
```
Propagation is transitive therefore ...
```
project "lib_b"
    kind "StaticLib"
    links {"lib_c"}

project "lib_a"
    kind "StaticLib"
    links {"lib_b"}

projects "exe"
    kind "ConsoleApp"
    links {"lib_a"} actually {"lib_a", "lib_b"}
```



