# mbed online compiler for cli

```moco``` is Mbed Online COmpiler for cli tool.

## Installation

```
# Can't work now. not publish rubygems.org yet.
$ gem install mbed-online-compiler-cli
```

## Set development.mbed.com username and password

```
# ~/.mocorc
options['username'] = 'hotchpotch'
options['password'] = 'your-password-string'
# can use keyring
# https://pypi.python.org/pypi/keyring
options['password'] = keyring
```

## compile by moco


```
$ cat main.cpp

#include "mbed.h"

Serial serial(USBTX, USBRX);

int main() {
    serial.print("Hello moco!\r\n");
}

```

Let's compile!

```
$ moco compile
Upload files: main.cpp
[FAILED] option `platform` is required.
should set command-line arguments or ~/.mocorc or ./.mocorc
...
  -b, [--platform=PLATFORM]
...
```

oops, you should set `platform` select your boards.

* Note: you must have the platform added your account on developer.mbed.org.

```
$ moco c -b ST-Nucleo-L476RG
Upload files: main.cpp
[FAILED] mbed online compile failed
Macros: -DTARGET_NUCLEO_L476RG -DTARGET_M4 -DTARGET_CORTEX_M ...
Compile: /opt/RVCT_5.05/bin/armcc -c --gnu -O3 -Otime ...
main.cpp:7:11:error: #135: class "mbed::Serial" has no member "print"
```

oops, fixed main.cpp.

```
#include "mbed.h"

Serial serial(USBTX, USBRX);

int main() {
    // change print to printf
    serial.printf("Hello moco!\r\n");
}
```

Let's retry!

```
$ moco c -b ST-Nucleo-L476RG
Upload files: main.cpp
Macros: -DTARGET_NUCLEO_L476RG -DTARGET_M4 -DTARGET_CORTEX_M ...
Compile: /opt/RVCT_5.05/bin/armcc -c --gnu -O3 -Otime ...
FromELF: /opt/RVCT_5.05/bin/fromelf --bin -o ...
Online compile successed! download firmare.
-> firmware(17332 byte): /my/workspace/moco_79267.NUCLEO_L476RG.bin
```

cool...

but I want to write firmware on mbed volume.

```
# -q is quiet option. -o is output_dir.
$ moco c -q -b ST-Nucleo-L476RG -o /Volumes/NODE_L476RG
Upload files: main.cpp
Online compile successed! download firmare.
-> firmware(17332 byte): /Volumes/NODE_L476RG/moco_79267.NUCLEO_L476RG.bin
```

It works! :)

## set repository option

```
$ rm main.cpp
$ moco c -r https://developer.mbed.org/teams/mbed/code/mbed_blinky/ -q -b ST-Nucleo-L476RG -o /Volumes/NODE_L476RG
```

my mbed board works blink! :)

### about .mocorc

moco read rc files ./.mocorc & ~/.mocorc

recommend setting is

```
# ~/.mocorc
options['username'] = 'hotchpotch'
options['password'] = keyring
```

```
# ./.mocorc
options['output_dir'] = '/Volumes/NODE_L476RG/'
options['platform'] = 'ST-Nucleo-L476RG'
```

## use developer.mbed.org repository

1. Your repository change status publish
2. hg get https://your_repos...
3. cd repos
4. moco c

It works!

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

