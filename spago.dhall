{-
Welcome to a Spago project!
You can edit this file as you like.
-}
{ name = "option"
, dependencies =
    [ "console"
    , "effect"
    , "either"
    , "foreign"
    , "foreign-object"
    , "lists"
    , "maybe"
    , "prelude"
    , "psci-support"
    , "record"
    , "tuples"
    , "unsafe-coerce"
    ]
, packages = ./packages.dhall
, sources = [ "src/**/*.purs", "test/**/*.purs" ]
}
