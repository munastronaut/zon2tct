# zon2tct

This is a Code 2 creation tool for the webgame *The Campaign Trail* and its
forks such as *[Campaign Trail Showcase](https://campaigntrailshowcase.com)*.

It allows for creating mods by writing the questions, answers, and the answer
feedback and effects of those answers, in a single file with a hierarchical
data structure. This tool then reads the input file and outputs a JavaScript
file with the hierarchical format converted to the relational format needed for
*The Campaign Trail*.

## How to download

### Shell scripts

There are two ways to install `zon2tct` through shell scripts. Both scripts can
be used in different environments, however it is recommended that you pick the
script which is most suitable for your operating system.

#### Bourne shell (\*NIX)

```sh
curl -fsSL https://raw.githubusercontent.com/munastronaut/zon2tct/refs/heads/main/install.sh | sh
```

This is the recommended method if you are on a \*NIX system like MacOS or Linux.

#### PowerShell (Windows)

```ps1
iwr https://raw.githubusercontent.com/munastronaut/zon2tct/refs/heads/main/install.ps1 | iex
```

This is the recommended method if you are on Windows.

### Manual downloads

Download the archive for your operating system (i.e. if on Windows 64-bit,
download `zon2tct-x86_64-windows-x.y.z.zip`). Each archive contains a single
executable file.

## How to use

If you are on Windows, `zon2tct` is invoked as `zon2tct.exe`.

To initialize a project:

```sh
zon2tct init --name '1972'
```

If `--name [name]` is omitted, the default project name is `scenario`.

To build a scenario:

```sh
zon2tct build scenario.zon -o code2.js
```

If `-o <file>` is omitted, the resulting JavaScript file is saved with the
basename of the input file (`scenario.zon` becomes `scenario.js`).

To see all possible commands:

```sh
zon2tct help
```

## Information

For any questions you might have regarding the tool, consult the
[FAQ](docs/FAQ.md).
