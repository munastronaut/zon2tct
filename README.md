# zon2tct

This is a Code 2 creation tool for the webgame *The Campaign Trail* and its forks such as *[Campaign Trail Showcase](https://campaigntrailshowcase.com)*.

It allows for creating mods by writing the questions, answers, and the answer feedback and effects of those answers, in a single file with a hierarchical data structure. This tool then reads the input file and outputs a JavaScript file with the hierarchical format converted to the relational format needed for *The Campaign Trail*.

## How to use

Download the archive for your operating system (i.e. if on Windows 64-bit, download `zon2tct-x86_64-windows-0.3.0.zip`). Each archive contains a single executable file. Usage is generally like this:

```
zon2tct build scenario.zon
```

If you are on Windows, you invoke it as `zon2tct.exe`. To initialize a project, you may invoke this command:

```
zon2tct init --name '1972'
```

If `--name [name]` is omitted, the default project name is `scenario`.

## Information

For any questions you might have regarding the tool, consult the [FAQ](docs/FAQ.md).
