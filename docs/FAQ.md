# FAQ

**Q: Does `zon2tct` handle the Code 1?**

No. `zon2tct` mainly focuses on the Code 2 of a mod, which is arguably the most exhausting — the questions, the answers, the feedback, and the effects. Existing tools are sufficient for this purpose, like Jet's Code 1 tool.

**Q: Why should I use this over Jet's or other tools?**

I would like to start off by saying, this is not meant to be a replacement for Jet's for the time being. Jet's maturity makes it excel in certain areas like generating the state and issue boilerplate. You should certainly use Jet's alongside `zon2tct`.

This tool offers a different workflow for mod creation and type safety at build time. You should consider using it if you value the following:

- **Line count and time.** The sample `1960.zon` file in the `examples` directory has 1853 lines. This produced a JavaScript file of 3556 lines. Also, in Jet's, it might be exhausting to click through layers upon layers of buttons to change a certain thing. This mostly allays that fatigue.
- **Speed.** One overused attribute to describe certain programs is the phrase "blazingly fast". As much as I hate to use it here, `zon2tct` is blazingly fast. It managed to transpile a file that defined the entirety of the 1960 scenario (excluding states and state issue scores and multipliers) in 7 milliseconds.
- **Automatic reindexing of PKs at build time.** In Jet's, adding a new state, question, effect, or any other object, increments a global counter by one. This may seem intuitive, but it can be a mess for PKs when it comes to deleting or changing the order of certain objects.
- **Diagnostics.** It's currently not that fleshed out, but it is a notable feature. Jet's will not warn you when you accidentally put in a double quote inside a text field, but this will warn you when you misspell an alias or use an alias defined in `.candidates` in a field expecting it to be defined in `.states`, at least, most of the time.
- **Better string handling.** One feature of Jet's is that the raw bytes are pasted into the code. This is fine for HTML tags like `<i>`, but one pitfall is that it doesn't properly escape raw double quotes, which is a frequent complaint in channels related to mod help.
- **Version control.** You are writing your mod in plaintext, which is easily diff-able. This makes it suitable for Git, which you can use to track changes and to collaborate with other modders on a mod team.

**Q: Will you be making a GUI version?**

As of now, not yet. But it is certainly possible to port this to WebAssembly and allow for a web interface, which will be done when this tool is mature enough.

**Q: Does `zon2tct` support CYOA?**

No, and it likely never will in a comprehensive manner. `zon2tct` is a program that converts your data to JavaScript code. Please do not click off, because I have a few reasons for not supporting CYOA.

First, `zon2tct` is not meant to be a programming language, it converts all your questions, answers, and the like, to the necessary JavaScript code the game needs.

Secondly, it is hard to implement with just a single modding tool. Jet's has support for CYOA, but it is slightly primitive, and you would have to track many things like conditionals, variables, and outcomes.

I recommend writing your CYOA manually in JavaScript, and there are great resources on learning JavaScript, like [javascript.info](https://javascript.info), which I used when I was learning JavaScript.

A more comprehensive explanation can be found [here](ON_CYOA.md).
