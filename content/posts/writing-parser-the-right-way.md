---
title: 'Writing parsers: the right way'
date: 2018-06-04T19:46:00+0100
comments: true
categories:
  - Antlr4
tags:
  - antlr4
  - c#
  - parser
---

At least once in your coding adventures you will land on writing your own
parser. Whether it is to read a custom text format or interpret a custom
language, the ultimate structure and solution will likely be the same. You will
need to create a module that takes strings as input and produces meaningful
data structures out of it. Let's see what the best approach to this task is by
taking on a parsing problem on a simple language and 'evolving' a solution of
our own.

To be exact, we'll be looking at parsing **.NET XML Documentation Comments**.
While this format is mostly XML, it does contain custom URI strings to denote a
code target (type, property, field etc.) for the documentation. Some examples
of these strings can be seen below.

```csharp
T:Microsoft.Extensions.DependencyInjection.Extensions.ServiceCollectionDescriptorExtensions
P:Microsoft.Extensions.DependencyInjection.ServiceDescriptor.ServiceType
M:Microsoft.Extensions.DependencyInjection.ServiceDescriptor.#ctor(System.Type,System.Object)
```

Looks fairly straightforward, right? Well... We shall see! Let's try to solve
this in a naïve way.

# Naïve approach

In the naïve case, the parsing problem is approached as a purely coding task.
While this may work for simple formats, the code often ends up rather ugly and
contains a number of bugs.

```csharp
public static XmlDocTargetBase Parse(string source)
{
    var prefix = source[0];
    var member = source.Substring(2);

    switch(prefix)
    {
        case PrefixType:
            return ParseType(member);
        case PrefixMethod:
            var temp = member.Substring(0, member.IndexOf('('));
            var parent = ParseType(temp.Substring(0, temp.LastIndexOf('.')));
            var method = temp.Substring(temp.LastIndexOf('.') + 1);
            temp = member.Substring(member.IndexOf('(') + 1);
            var arguments = temp.Split(',').Select(ParseType).ToArray();
            return new XmlDocMethodTarget
            {
                Parent = parent,
                Method = method,
            };
            ...
```

Code like this is not unusual for parsing - let's pick it apart to underline
why exactly it is bad.

First of all, it relies on a number of magical
constants: it uses characters like dot/parenthesis and offsets to identify
individual parts of the string. Hard-coding offsets is prone to errors (infamous
off-by-one error), as it is difficult to follow the code and, as a result, it
isn't immediately clear why offset has the value it does.

Secondly, it's difficult to consider all the edge cases and the code looks
really clunky if you do do this. For example,
[String.IndexOf](<https://msdn.microsoft.com/en-us/library/k8b1470s(v=vs.110).aspx>)
and
[String.LastIndexOf](<https://msdn.microsoft.com/en-us/library/system.string.lastindexof(v=vs.110).aspx>)
can return **-1** if the token we are looking for could not be found.
Additionally, we need to check the length of the string before indexing to
ensure that it's long enough.

If you still are convinced that writing a parser manually would work out,
let's look at more advanced cases of the chosen format. Personally, I think the
generic types push this over the edge and suggest looking for a better
approach.

```csharp
M:Microsoft.Extensions.DependencyInjection.Extensions.ServiceCollectionDescriptorExtensions.TryAddTransient``1(Microsoft.Extensions.DependencyInjection.IServiceCollection)
M:Microsoft.Extensions.DependencyInjection.Extensions.ServiceCollectionDescriptorExtensions.TryAddEnumerable(Microsoft.Extensions.DependencyInjection.IServiceCollection,System.Collections.Generic.IEnumerable{Microsoft.Extensions.DependencyInjection.ServiceDescriptor})
```

# Scientific(?) approach

If you've done a course in Computer Science, you probably have been introduced
to a more formal approach to parsing - using grammars. In this case, grammar is
a set of rules that defines what the format must look like. Grammars are laid
out in a logical way and enable you to effortlessly cover all the edge cases we
previously discussed.

I have chosen [antlr4](http://www.antlr.org/) for this article, which stands
for **ANother Tool for Language Recognition**. This is a rather popular choice
that is supported well by both the community and industry (Microsoft used it
in ASP.NET to optimise CSS/JS). More importantly, it supports generating
parsers in many programming languages including C#, which means that we'll be
able to integrate with it easily. You can follow the official guide (linked
above) to get your copy of **antlr4** up and running.

## Writing a grammar

So, let's dive into declaring our first very own grammar. The grammar we shall
build will cover a simple case of  
`T:Microsoft.Extensions.DependencyInjection.Extensions.ServiceCollectionDescriptorExtensions`
and ignore any whitespace. Before formalising the grammar, we need to break
down this string into the individual components. First of all, we can see that
it starts with a prefix `T:`, which indicates that the code unit is a C# type.
It is then followed by namespace  
`Microsoft.Extensions.DependencyInjection.Extensions`, which is made of
individual components `Microsoft`, `Extensions`, `DependencyInjection` and
`Extensions`. Finally, the string is concluded with
`ServiceCollectionDescriptorExtensions` after a dot, which is a type name.

Now, let's formalise these rules in **antlr4** grammar format. We shall start
with the top-level rules. The grammar below defines the components of the
string exactly the same way as we established previously.

```ruby
grammar XmlDocTarget;

target
    : type_target
    ;

type_target
    : 'T:' type
    ;

type
    : namespace '.' type_name
    ;
```

Now, we need to define what `namespace` is. As we mentioned previously, the
namespace is a sequence of dot-separated components. Based on our C# knowledge,
we also know that all types have to be enclosed with a namespace. This means
that at least one namespace component has to be present. We can formalise this
rule in the following manner.

```ruby
namespace
    : namespace_component ('.' namespace_component)*
    ;
```

Here you can see a classic pattern for defining a sequence to parse. If you
have done regular expressions before, you will find this rule quite
straightforward to interpret. Basically, we expect at least one
`namespace_component` to be present. Afterwards, **0 or more** (defined by `*`)
`namespace_component` items can follow, each prepended with a dot. This will
match both simple namespaces (e.g., **System**) and more complex ones (e.g.,
**System.Xml.Serialization**).

Descending on a lower level, we now need to define what `namespace_component`
and `type_name` is. Both of these are C# code entity names, so they have to be
alphanumeric and start with a letter. This can be represented by the following
regular expression `[a-zA-Z][a-zA-Z0-9]*`. This can be formalised with the
following grammar rules (note that all-caps rules are lexer rule).

```ruby
namespace_component
    : ENTITY_NAME
    ;

type_name
    : ENTITY_NAME
    ;

ENTITY_NAME
    : [a-zA-Z][a-zA-Z0-9]*
    ;
```

After combining all of these rules together, we will end up with a grammar
below. While it may seem a bit excessive at first, these building blocks save
us a lot of time later on when more advanced constructs are added. Note that
we also added a rule for whitespace and redirected matching tokens to
a **hidden** channel, which allows us to ignore whitespace.

```ruby
grammar XmlDocTarget;

target
    : type_target
    ;

type_target
    : TYPE_PREFIX type
    ;

type
    : namespace '.' type_name
    ;

namespace
    : namespace_component ('.' namespace_component)*
    ;

namespace_component
    : ENTITY_NAME
    ;

type_name
    : ENTITY_NAME
    ;

ENTITY_NAME
    : [a-zA-Z][a-zA-Z0-9]*
    ;

WHITESPACE
    : [\n]
    -> channel(HIDDEN)
    ;
```

**antlr4** is a parser generator, so it generates a parser in the given
programming language. We can generate a parser from our grammar using the
command shown below. As you can see, the system is made of 2 primary
components: lexer and parser. This is something we previously omitted for
simplicity, but essentially lexer converts text into low-level tokens whilst
parser combines them into high-level structures with rules.

```bash
$ antlr4 XmlDocTarget.g4 && ls -1 *.java
XmlDocTargetBaseListener.java
XmlDocTargetLexer.java
XmlDocTargetListener.java
XmlDocTargetParser.java
```

Needless to say, we will also need to compile the parser before we can use it.
This can be done with a classic invocation of Java compiler, `javac`.
Afterwards, we can attempt to parse the above-mentioned string.

```bash
$ javac *.java
$ echo "T:Microsoft.Extensions.DependencyInjection.Extensions.ServiceCollectionDescriptorExtensions" \
    | grun XmlDocTarget target -tree
(target
    (type T:
        (namespace
            (namespace_component Microsoft) .
            (namespace_component Extensions) .
            (namespace_component DependencyInjection) .
            (namespace_component Extensions)
        )
        .
        (type_name ServiceCollectionDescriptorExtensions)
    )
)
```

As you can see, we have successfully parsed the string into a type declaration.
Using similar techniques, we can extend the grammar to parse other entities
like methods, properties, fields and alike. After developing the parser, the
question becomes - how do we utilise it in our program? Previously, you might
have noticed that **antlr4** CLI tool generates Java code. Luckily, that's not
the only generator available - languages like Python, C#, C++, Go and others
are available.

## Generating a parser

In my case, I was interested in making use of the parser in C# programming
language. Pure C# solution (i.e., one that does not require Java installed) is
currently available as pre-release
[Antlr4.CodeGenerator 4.6.5 package](https://www.nuget.org/packages/Antlr4.CodeGenerator/4.6.5-rc002).
Integrating it into your build process is as simple as dropping a few lines
into your **.csproj** file.

```xml
<Project Sdk="Microsoft.NET.Sdk">
  ...
  <PropertyGroup>
    ...
    <Antlr4UseCSharpGenerator>True</Antlr4UseCSharpGenerator>
  </PropertyGroup>
  <ItemGroup>
    <Antlr4 Include="MyGrammar.g4">
      <Generator>MSBuild:Compile</Generator>
      <CustomToolNamespace>MyProject.MyNamespace</CustomToolNamespace>
      <Listener>False</Listener>
      <Visitor>False</Visitor>
    </Antlr4>
  </ItemGroup>
  <ItemGroup>
    ...
    <PackageReference Include="Antlr4.CodeGenerator" Version="4.6.5-rc002" />
    <PackageReference Include="Antlr4.Runtime" Version="4.6.4" />
  </ItemGroup>
  ...
</Project>
```

This solution is fully integrated into your project and works in all
development (Visual Studio, Visual Studio Code etc.) and integration
environments (TFS Build, CLI etc.). This means that building your project
remains a simple **msbuild** invocation. Additionally, you avoid checking in
auto-generated files into source control (which is a good practice).
Unlike Visual Studio Code, Visual Studio is also smart enough to perform
auto-complete on the auto-generated files (Parser/Lexer classes).

## Integrating with antlr4

The lexer and parser will be generated in the `CustomToolNamespace` we
specified. However, there still is a bit of glue code required in order to turn
an arbitrary string into meaningful objects. Firstly, we need to initialise the
**antlr4** parsing pipeline.

```csharp
var source = "T:Microsoft.Extensions.DependencyInjection.Extensions.ServiceCollectionDescriptorExtensions";
var inputStream = new AntlrInputStream(source);
var lexer = new XmlDocTargetLexer(inputStream);
var tokenStream = new CommonTokenStream(lexer);
var parser = new XmlDocTargetParser(tokenStream);
```

Having created a parser, we are now capable of extracting the knowledge from
the parse tree that the former produces. **antlr4** offers two different
approaches for this task: listener and visitor. First one is based on the idea
of listening for tokens, accumulating knowledge in the listener state and
returning it when requested. Needless to say, using this pattern will likely
result in a large amount of long listener classes. The second approach is based
on the idea that there is a one-to-one mapping between grammar rules and
business objects. While this may not work for all the grammars, it allows us to
avoid writing unnecessary code. This factor is what pushed us to opt for the
visitor pattern. The generation of a visitor base class can be enabled by
toggling `Visitor` to **true** in your **.csproj** file.

```csharp
internal class TypeTargetVisitor
    : XmlDocTargetBaseVisitor<XmlDocTargetType>
{
    public override XmlDocTargetType VisitSimple_type(XmlDocTargetParser.Simple_typeContext context)
    {
        var ns = context.@namespace().GetText();
        var type = context.type_name().GetText();
        return new XmlDocTargetType
        {
            Namespace = ns,
            Type = type
        };
    }
}
```

As you can see in a very basic example above, we transform a `simple_type` rule
into an `XmlDocTargetType` instance. This code can then be further extended to
support translation of other rules. Making use of the visitor we created is
also fairly straightforward, see the snippet below for reference (`parser` is
the object we created earlier).

```csharp
var target = visitor.Visit(parser.target());
```

Smashing! This way you can parse your custom text formats with ease and knowing
that it's virtually unbreakable. What is more, your code will remain lean and
easily readable. So, happy parsing and see you again!
