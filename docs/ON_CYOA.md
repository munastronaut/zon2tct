> *Any sufficiently complicated C or Fortran program contains an ad hoc, informally-specified, bug-ridden, slow implementation of half of Common Lisp.*
>
>\- *Philip Greenspun*

CMake is one of the most used build systems, yet one of the most hated. Its criticisms are not limited to just the syntax. CMake — a declarative DSL meant for clean cross-compilation of C and C++ programs — ended up being Turing complete, most likely by accident. But what does this have to do with *The Campaign Trail* and Choose Your Own Adventure?

Alan Mathison Turing — then a Master's student at Cambridge — came up with a novel type of "computer". Armed with a strip of tape of infinite length, this machine could implement any computer algorithm, meaning, it can basically do anything. His doctoral advisor, the famous Alonzo Church, later dubbed this a "Turing machine". And it is here that the terms Turing complete and Turing machine began to spread across the world of computer science.

For a general-purpose programming language to do anything and be, well, general-purpose, it must meet certain criteria. One criterion is that it must be Turing complete, in that, it can simulate a Turing machine, which consequently makes it able to do anything. Some of the most notable programming languages are Turing complete. C, C++ (which, fun fact, is formally undecidable when it comes to parsability! That means it is impossible for the parser to determine whether a given input string is syntactically valid or not), Python, and JavaScript.

JavaScript is a general-purpose programming language, and from that, we can deduce that it is Turing complete, which means that, as explained earlier, it can simulate any Turing machine. Which consequently means that it is capable of implementing any arbitrary algorithm. Being the scripting language of the web, it means that for a website to implement basic scripting, it has to use JavaScript. The original *The Campaign Trail* was written in JavaScript, and its descendants have been written in JavaScript ever since.

When TCT forks like *New Campaign Trail* and *Campaign Trail Showcase* implement CYOA, what they are actually giving you is a global function that is exposed to you, which allows you to redefine the body of the function. This is — in a way — an algorithm. The engine calls this function, usually named `cyoAdventure`, on every question.

For `zon2tct` to support every aspect of CYOA would lead us down the same path that CMake walked — eventually, `zon2tct` will be a Turing complete Frankenstein monster of curly braces, conditionals, variables, and other things. Recalling the adage from earlier, **any sufficiently complicated CYOA engine for a modding tool contains an ad-hoc, informally-specified, bug-ridden, slow implementation of half of JavaScript.**
