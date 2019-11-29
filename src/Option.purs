-- | There are a few different data types that encapsulate ideas in programming.
-- |
-- | Records capture the idea of a collection of key/value pairs where every key and value exist.
-- | E.g. `Record (foo :: Boolean, bar :: Int)` means that both `foo` and `bar` exist and with values all of the time.
-- |
-- | Variants capture the idea of a collection of key/value pairs where exactly one of the key/value pairs exist.
-- | E.g. `Variant (foo :: Boolean, bar :: Int)` means that either only `foo` exists with a value or only `bar` exists with a value, but not both at the same time.
-- |
-- | Options capture the idea of a collection of key/value pairs where any key and value may or may not exist.
-- | E.g. `Option (foo :: Boolean, bar :: Int)` means that either only `foo` exists with a value, only `bar` exists with a value, both `foo` and `bar` exist with values, or neither `foo` nor `bar` exist.
-- |
-- | The distinction between these data types means that we can describe problems more accurately.
-- | Options are typically what you find in dynamic languages or in weakly-typed static languages.
-- | Their use cases range from making APIs more flexible to interfacing with serialization formats to providing better ergonomics around data types.
module Option
  ( Option
  , delete
  , empty
  , get
  , insert
  , modify
  , set
  , disjointUnion
  , fromRecord
  , fromRecord_
  , toRecord
  , class EqOption
  , eqOption
  , class OrdOption
  , compareOption
  , class ShowOption
  , showOption
  , class FromRecord
  , fromRecord'
  , class FromRecordOption
  , fromRecordOption
  , class ToRecord
  , toRecord'
  , class ToRecordOption
  , toRecordOption
  ) where

import Prelude

import Data.List as Data.List
import Data.Maybe as Data.Maybe
import Data.Symbol as Data.Symbol
import Foreign.Object as Foreign.Object
import Prim.Row as Prim.Row
import Prim.RowList as Prim.RowList
import Record as Record
import Unsafe.Coerce as Unsafe.Coerce

-- | A collection of key/value pairs where any key and value may or may not exist.
-- | E.g. `Option (foo :: Boolean, bar :: Int)` means that either only `foo` exists with a value, only `bar` exists with a value, both `foo` and `bar` exist with values, or neither `foo` nor `bar` exist.
newtype Option (row :: #Type)
  = Option (Foreign.Object.Object (forall a. a))

-- A local proxy for `Prim.RowList.RowList` so as not to impose a hard requirement on `Type.Data.RowList.RLProxy` in the typeclasses we define.
-- `Type.Data.RowList.RLProxy` can still be used by callers, but it's not a requirement.
data Proxy (list :: Prim.RowList.RowList)
  = Proxy

instance eqOptionOption ::
  ( EqOption list option
  , Prim.RowList.RowToList option list
  ) =>
  Eq (Option option) where
  eq = eqOption (Proxy :: Proxy list)

instance ordOptionOption ::
  ( OrdOption list option
  , Prim.RowList.RowToList option list
  ) =>
  Ord (Option option) where
  compare = compareOption (Proxy :: Proxy list)

instance showOptionOption ::
  ( Prim.RowList.RowToList option list
  , ShowOption list option
  ) =>
  Show (Option option) where
  show ::
    Option option ->
    String
  show option = "(Option.fromRecord {" <> go fields <> "})"
    where
    fields :: Data.List.List String
    fields = showOption proxy option

    go :: Data.List.List String -> String
    go x' = case x' of
      Data.List.Cons x Data.List.Nil -> " " <> x <> " "
      Data.List.Cons x y -> " " <> go' x y <> " "
      Data.List.Nil -> ""

    go' :: String -> Data.List.List String -> String
    go' acc x' = case x' of
      Data.List.Cons x y -> go' (acc <> ", " <> x) y
      Data.List.Nil -> acc

    proxy :: Proxy list
    proxy = Proxy

-- | A typeclass that iterates a `RowList` converting an `Option _` to a `Boolean`.
class EqOption (list :: Prim.RowList.RowList) (option :: #Type) | list -> option where
  -- | The `proxy` can be anything so long as its type variable has kind `Prim.RowList.RowList`.
  -- |
  -- | It will commonly be `Type.Data.RowList.RLProxy`, but doesn't have to be.
  eqOption ::
    forall proxy.
    proxy list ->
    Option option ->
    Option option ->
    Boolean

instance eqOptionNil :: EqOption Prim.RowList.Nil () where
  eqOption ::
    forall proxy.
    proxy Prim.RowList.Nil ->
    Option () ->
    Option () ->
    Boolean
  eqOption _ _ _ = true
else instance eqOptionCons ::
  ( Data.Symbol.IsSymbol label
  , Eq value
  , EqOption list option'
  , Prim.Row.Cons label value option' option
  , Prim.Row.Lacks label option'
  ) =>
  EqOption (Prim.RowList.Cons label value list) option where
  eqOption ::
    forall proxy.
    proxy (Prim.RowList.Cons label value list) ->
    Option option ->
    Option option ->
    Boolean
  eqOption _ left' right' = leftValue == rightValue && rest
    where
    key :: String
    key = Data.Symbol.reflectSymbol label

    label :: Data.Symbol.SProxy label
    label = Data.Symbol.SProxy

    left :: Option option'
    left = delete label left'

    leftValue :: Data.Maybe.Maybe value
    leftValue = get label left'

    proxy :: Proxy list
    proxy = Proxy

    rest :: Boolean
    rest = eqOption proxy left right

    right :: Option option'
    right = delete label right'

    rightValue :: Data.Maybe.Maybe value
    rightValue = get label right'

-- | A typeclass for converting a `Record _` into an `Option _`.
-- |
-- | An instance `FromRecord record option` states that we can make an `Option option` from a `Record record` where every field present in the record is present in the option.
-- | E.g. `FromRecord () ( name :: String )` says that the `Option ( name :: String )` will have no value; and `FromRecord ( name :: String ) ( name :: String )` says that the `Option ( name :: String )` will have the given `name` value.
-- |
-- | Since there is syntax for creating records, but no syntax for creating options, this typeclass can be useful for providing an easier to use interface to options.
-- |
-- | E.g. Someone can say:
-- | ```PureScript
-- | Option.fromRecord' { foo: true, bar: 31 }
-- | ```
-- | Instead of having to say:
-- | ```PureScript
-- | Option.insert
-- |   (Data.Symbol.SProxy :: _ "foo")
-- |   true
-- |   ( Option.insert
-- |       (Data.Symbol.SProxy :: _ "bar")
-- |       31
-- |       Option.empty
-- |   )
-- | ```
-- |
-- | Not only does it save a bunch of typing, it also mitigates the need for a direct dependency on `SProxy _`.
class FromRecord (record :: #Type) (option :: #Type) where
  -- | The given `Record record` must have no more fields than the expected `Option _`.
  -- |
  -- | E.g. The following definitions are valid.
  -- | ```PureScript
  -- | option1 :: Option.Option ( foo :: Boolean, bar :: Int )
  -- | option1 = Option.fromRecord' { foo: true, bar: 31 }
  -- |
  -- | option2 :: Option.Option ( foo :: Boolean, bar :: Int )
  -- | option2 = Option.fromRecord' {}
  -- | ```
  -- |
  -- | However, the following definitions are not valid as the given records have more fields than the expected `Option _`.
  -- | ```PureScript
  -- | -- This will not work as it has the extra field `baz`
  -- | option3 :: Option.Option ( foo :: Boolean, bar :: Int )
  -- | option3 = Option.fromRecord' { foo: true, bar: 31, baz: "hi" }
  -- |
  -- | -- This will not work as it has the extra field `qux`
  -- | option4 :: Option.Option ( foo :: Boolean, bar :: Int )
  -- | option4 = Option.fromRecord' { qux: [] }
  -- | ```
  fromRecord' :: Record record -> Option option

-- | This instance converts a record into an option.
-- |
-- | Every field in the record is added to the option.
-- |
-- | Any fields in the expected option that do not exist in the record are not added.
instance fromRecordAny ::
  ( FromRecordOption list record option
  , Prim.RowList.RowToList record list
  ) =>
  FromRecord record option where
  fromRecord' :: Record record -> Option option
  fromRecord' = fromRecordOption (Proxy :: Proxy list)

-- | A typeclass that iterates a `RowList` converting a `Record _` into an `Option _`.
class FromRecordOption (list :: Prim.RowList.RowList) (record :: #Type) (option :: #Type) | list -> option record where
  -- | The `proxy` can be anything so long as its type variable has kind `Prim.RowList.RowList`.
  -- |
  -- | It will commonly be `Type.Data.RowList.RLProxy`, but doesn't have to be.
  fromRecordOption ::
    forall proxy.
    proxy list ->
    Record record ->
    Option option

instance fromRecordOptionNil :: FromRecordOption Prim.RowList.Nil () option where
  fromRecordOption ::
    forall proxy.
    proxy Prim.RowList.Nil ->
    Record () ->
    Option option
  fromRecordOption _ _ = empty
else instance fromRecordOptionCons ::
  ( Data.Symbol.IsSymbol label
  , FromRecordOption list record' option'
  , Prim.Row.Cons label value option' option
  , Prim.Row.Cons label value record' record
  , Prim.Row.Lacks label option'
  , Prim.Row.Lacks label record'
  ) =>
  FromRecordOption (Prim.RowList.Cons label value list) record option where
  fromRecordOption ::
    forall proxy.
    proxy (Prim.RowList.Cons label value list) ->
    Record record ->
    Option option
  fromRecordOption _ record = insert label value option
    where
    label :: Data.Symbol.SProxy label
    label = Data.Symbol.SProxy

    option :: Option option'
    option = fromRecordOption proxy record'

    proxy :: Proxy list
    proxy = Proxy

    record' :: Record record'
    record' = Record.delete label record

    value :: value
    value = Record.get label record

-- | A typeclass that iterates a `RowList` converting an `Option _` to a `Boolean`.
class
  (EqOption list option) <= OrdOption (list :: Prim.RowList.RowList) (option :: #Type) | list -> option where
  -- | The `proxy` can be anything so long as its type variable has kind `Prim.RowList.RowList`.
  -- |
  -- | It will commonly be `Type.Data.RowList.RLProxy`, but doesn't have to be.
  compareOption ::
    forall proxy.
    proxy list ->
    Option option ->
    Option option ->
    Ordering

instance ordOptionNil :: OrdOption Prim.RowList.Nil () where
  compareOption ::
    forall proxy.
    proxy Prim.RowList.Nil ->
    Option () ->
    Option () ->
    Ordering
  compareOption _ _ _ = EQ
else instance ordOptionCons ::
  ( Data.Symbol.IsSymbol label
  , Ord value
  , OrdOption list option'
  , Prim.Row.Cons label value option' option
  , Prim.Row.Lacks label option'
  ) =>
  OrdOption (Prim.RowList.Cons label value list) option where
  compareOption ::
    forall proxy.
    proxy (Prim.RowList.Cons label value list) ->
    Option option ->
    Option option ->
    Ordering
  compareOption _ left' right' = case compare leftValue rightValue of
    EQ -> rest
    GT -> GT
    LT -> LT
    where
    key :: String
    key = Data.Symbol.reflectSymbol label

    label :: Data.Symbol.SProxy label
    label = Data.Symbol.SProxy

    left :: Option option'
    left = delete label left'

    leftValue :: Data.Maybe.Maybe value
    leftValue = get label left'

    proxy :: Proxy list
    proxy = Proxy

    rest :: Ordering
    rest = compareOption proxy left right

    right :: Option option'
    right = delete label right'

    rightValue :: Data.Maybe.Maybe value
    rightValue = get label right'

-- | A typeclass that iterates a `RowList` converting an `Option _` to a `List String`.
-- | The `List String` should be processed into a single `String`.
class ShowOption (list :: Prim.RowList.RowList) (option :: #Type) | list -> option where
  -- | The `proxy` can be anything so long as its type variable has kind `Prim.RowList.RowList`.
  -- |
  -- | It will commonly be `Type.Data.RowList.RLProxy`, but doesn't have to be.
  showOption ::
    forall proxy.
    proxy list ->
    Option option ->
    Data.List.List String

instance showOptionNil :: ShowOption Prim.RowList.Nil () where
  showOption ::
    forall proxy.
    proxy Prim.RowList.Nil ->
    Option () ->
    Data.List.List String
  showOption _ _ = Data.List.Nil
else instance showOptionCons ::
  ( Data.Symbol.IsSymbol label
  , Show value
  , ShowOption list option'
  , Prim.Row.Cons label value option' option
  , Prim.Row.Lacks label option'
  ) =>
  ShowOption (Prim.RowList.Cons label value list) option where
  showOption ::
    forall proxy.
    proxy (Prim.RowList.Cons label value list) ->
    Option option ->
    Data.List.List String
  showOption _ option = case value' of
    Data.Maybe.Just value -> Data.List.Cons (key <> ": " <> show value) rest
    Data.Maybe.Nothing -> rest
    where
    key :: String
    key = Data.Symbol.reflectSymbol label

    label :: Data.Symbol.SProxy label
    label = Data.Symbol.SProxy

    option' :: Option option'
    option' = delete label option

    proxy :: Proxy list
    proxy = Proxy

    rest :: Data.List.List String
    rest = showOption proxy option'

    value' :: Data.Maybe.Maybe value
    value' = get label option

-- | A typeclass for converting an `Option _` into a `Record _`.
-- |
-- | Since there is syntax for operating on records, but no syntax for operating on options, this typeclass can be useful for providing an easier to use interface to options.
-- |
-- | E.g. Someone can say:
-- | ```PureScript
-- | (Option.toRecord' someOption).foo
-- | ```
-- | Instead of having to say:
-- | ```PureScript
-- | Option.get (Data.Symbol.SProxy :: _ "foo") someOption
-- | ```
-- |
-- | Not only does it save a bunch of typing, it also mitigates the need for a direct dependency on `SProxy _`.
class ToRecord (option :: #Type) (record :: #Type) | option -> record where
  -- | The expected `Record record` will have the same fields as the given `Option _` where each type is wrapped in a `Maybe`.
  -- |
  -- | E.g.
  -- | ```PureScript
  -- | someOption :: Option.Option ( foo :: Boolean, bar :: Int )
  -- | someOption = Option.fromRecord' { foo: true, bar: 31 }
  -- |
  -- | someRecord :: Record ( foo :: Data.Maybe.Maybe Boolean, bar :: Data.Maybe.Maybe Int )
  -- | someRecord = Option.toRecord' someOption
  -- | ```
  toRecord' ::
    Option option ->
    Record record

-- | This instance converts an option into a record.
-- |
-- | Every field in the option is added to a record with a `Maybe _` type.
-- |
-- | All fields in the option that exist will have the value `Just _`.
-- | All fields in the option that do not exist will have the value `Nothing`.
instance toRecordAny ::
  ( ToRecordOption list option record
  , Prim.RowList.RowToList record list
  ) =>
  ToRecord option record where
  toRecord' ::
    Option option ->
    Record record
  toRecord' = toRecordOption (Proxy :: Proxy list)

-- | A typeclass that iterates a `RowList` converting an `Option _` into a `Record _`.
class ToRecordOption (list :: Prim.RowList.RowList) (option :: #Type) (record :: #Type) | list -> option record where
  -- | The `proxy` can be anything so long as its type variable has kind `Prim.RowList.RowList`.
  -- |
  -- | It will commonly be `Type.Data.RowList.RLProxy`, but doesn't have to be.
  toRecordOption ::
    forall proxy.
    proxy list ->
    Option option ->
    Record record

instance toRecordOptionNil ::
  ToRecordOption Prim.RowList.Nil () () where
  toRecordOption ::
    forall proxy.
    proxy Prim.RowList.Nil ->
    Option () ->
    Record ()
  toRecordOption _ _ = {}
else instance toRecordOptionCons ::
  ( Data.Symbol.IsSymbol label
  , Prim.Row.Cons label value option' option
  , Prim.Row.Cons label (Data.Maybe.Maybe value) record' record
  , Prim.Row.Lacks label option'
  , Prim.Row.Lacks label record'
  , ToRecordOption list option' record'
  ) =>
  ToRecordOption (Prim.RowList.Cons label (Data.Maybe.Maybe value) list) option record where
  toRecordOption ::
    forall proxy.
    proxy (Prim.RowList.Cons label (Data.Maybe.Maybe value) list) ->
    Option option ->
    Record record
  toRecordOption _ option = Record.insert label value record
    where
    label :: Data.Symbol.SProxy label
    label = Data.Symbol.SProxy

    record :: Record record'
    record = toRecordOption proxy option'

    proxy :: Proxy list
    proxy = Proxy

    option' :: Option option'
    option' = delete label option

    value :: Data.Maybe.Maybe value
    value = get label option

-- Do not export this value. It can be abused to invalidate invariants.
alter ::
  forall label option option' proxy value value'.
  Data.Symbol.IsSymbol label =>
  (Data.Maybe.Maybe value' -> Data.Maybe.Maybe value) ->
  proxy label ->
  Option option' ->
  { option :: Option option, value :: Data.Maybe.Maybe value }
alter f proxy (Option object) = { option, value }
  where
  from :: forall a. Data.Maybe.Maybe a -> Data.Maybe.Maybe value'
  from = Unsafe.Coerce.unsafeCoerce

  go :: forall a. Data.Maybe.Maybe a -> Data.Maybe.Maybe a
  go value' = to (f (from value'))

  key :: String
  key = Data.Symbol.reflectSymbol (Data.Symbol.SProxy :: Data.Symbol.SProxy label)

  option :: Option option
  option = Option (Foreign.Object.alter go key object)

  to :: forall a. Data.Maybe.Maybe value -> Data.Maybe.Maybe a
  to = Unsafe.Coerce.unsafeCoerce

  value :: Data.Maybe.Maybe value
  value = f (from (Foreign.Object.lookup key object))

-- | Removes a key from an option
-- |
-- | ```PureScript
-- | someOption :: Option.Option ( foo :: Boolean, bar :: Int )
-- | someOption = Option.fromRecord { foo: true, bar: 31 }
-- |
-- | anotherOption :: Option.Option ( bar :: Int )
-- | anotherOption = Option.delete (Data.Symbol.SProxy :: _ "foo") someOption
-- | ```
-- |
-- | The `proxy` can be anything so long as its type variable has kind `Symbol`.
-- |
-- | It will commonly be `Data.Symbol.SProxy`, but doesn't have to be.
delete ::
  forall label option option' proxy value.
  Data.Symbol.IsSymbol label =>
  Prim.Row.Cons label value option option' =>
  Prim.Row.Lacks label option =>
  proxy label ->
  Option option' ->
  Option option
delete proxy option = (alter go proxy option).option
  where
  go :: forall a. a -> Data.Maybe.Maybe value
  go _ = Data.Maybe.Nothing

-- | Creates an option with no key/values that matches any type of option.
-- |
-- | This can be useful as a starting point for an option that is later built up.
-- |
-- | E.g.
-- | ```PureScript
-- | someOption :: Option.Option ( foo :: Boolean, bar :: Int )
-- | someOption = Option.empty
-- |
-- | anotherOption :: Option.Option ( foo :: Boolean, bar :: Int )
-- | anotherOption = Option.set (Data.Symbol.SProxy :: _ "bar") 31 Option.empty
-- | ```
empty :: forall option. Option option
empty = Option Foreign.Object.empty

-- | The given `Record record` must have no more fields than the expected `Option _`.
-- |
-- | E.g. The following definitions are valid.
-- | ```PureScript
-- | option1 :: Option.Option ( foo :: Boolean, bar :: Int )
-- | option1 = Option.fromRecord { foo: true, bar: 31 }
-- |
-- | option2 :: Option.Option ( foo :: Boolean, bar :: Int )
-- | option2 = Option.fromRecord {}
-- | ```
-- |
-- | However, the following definitions are not valid as the given records have more fields than the expected `Option _`.
-- | ```PureScript
-- | -- This will not work as it has the extra field `baz`
-- | option3 :: Option.Option ( foo :: Boolean, bar :: Int )
-- | option3 = Option.fromRecord { foo: true, bar: 31, baz: "hi" }
-- |
-- | -- This will not work as it has the extra field `qux`
-- | option4 :: Option.Option ( foo :: Boolean, bar :: Int )
-- | option4 = Option.fromRecord { qux: [] }
-- | ```
-- |
-- | This is an alias for `fromRecord'` so the documentation is a bit clearer.
fromRecord ::
  forall option record.
  FromRecord record option =>
  Record record ->
  Option option
fromRecord = fromRecord'

-- | Like `fromRecord` but where Record and Option have same fields.
-- | This is mostly for type inference.
fromRecord_
  :: forall option
   . FromRecord option option
  => Record option
  -> Option option
fromRecord_ = fromRecord'

-- | Attempts to fetch the value at the given key from an option.
-- |
-- | If the key exists in the option, `Just _` is returned.
-- |
-- | If the key does not exist in the option, `Nothing` is returned.
-- |
-- | E.g.
-- | ```PureScript
-- | someOption :: Option.Option ( foo :: Boolean, bar :: Int )
-- | someOption = Option.insert (Data.Symbol.SProxy :: _ "bar") 31 Option.empty
-- |
-- | bar :: Data.Maybe.Maybe Int
-- | bar = Option.get (Data.Symbol.SProxy :: _ "bar") someOption
-- | ```
-- |
-- | The `proxy` can be anything so long as its type variable has kind `Symbol`.
-- |
-- | It will commonly be `Data.Symbol.SProxy`, but doesn't have to be.
get ::
  forall label option option' proxy value.
  Data.Symbol.IsSymbol label =>
  Prim.Row.Cons label value option' option =>
  proxy label ->
  Option option ->
  Data.Maybe.Maybe value
get proxy option = (alter go proxy option).value
  where
  go :: Data.Maybe.Maybe value -> Data.Maybe.Maybe value
  go value = value

-- | Adds a new key with the given value to an option.
-- | The key must not already exist in the option.
-- | If the key might already exist in the option, `set` should be used instead.
-- |
-- | E.g.
-- | ```PureScript
-- | someOption :: Option.Option ( foo :: Boolean )
-- | someOption = Option.empty
-- |
-- | anotherOption :: Option.Option ( foo :: Boolean, bar :: Int )
-- | anotherOption = Option.insert (Data.Symbol.SProxy :: _ "bar") 31 someOption
-- | ```
-- |
-- | The `proxy` can be anything so long as its type variable has kind `Symbol`.
-- |
-- | It will commonly be `Data.Symbol.SProxy`, but doesn't have to be.
insert ::
  forall label option option' proxy value.
  Data.Symbol.IsSymbol label =>
  Prim.Row.Cons label value option' option =>
  Prim.Row.Lacks label option' =>
  proxy label ->
  value ->
  Option option' ->
  Option option
insert proxy value option = (alter go proxy option).option
  where
  go :: forall a. a -> Data.Maybe.Maybe value
  go _ = Data.Maybe.Just value


-- | Manipulates the value of a key in an option.
-- |
-- | If the field exists in the option, the given function is applied to the value.
-- |
-- | If the field does not exist in the option, there is no change to the option.
-- |
-- | E.g.
-- | ```PureScript
-- | someOption :: Option.Option ( foo :: Boolean, bar :: Int )
-- | someOption = Option.insert (Data.Symbol.SProxy :: _ "bar") 31 Option.empty
-- |
-- | anotherOption :: Option.Option ( foo :: Boolean, bar :: Int )
-- | anotherOption = Option.modify (Data.Symbol.SProxy :: _ "bar") (_ + 1) someOption
-- | ```
-- |
-- | The `proxy` can be anything so long as its type variable has kind `Symbol`.
-- |
-- | It will commonly be `Data.Symbol.SProxy`, but doesn't have to be.
modify ::
  forall label option option' option'' proxy value value'.
  Data.Symbol.IsSymbol label =>
  Prim.Row.Cons label value' option'' option' =>
  Prim.Row.Cons label value option'' option =>
  proxy label ->
  (value' -> value) ->
  Option option' ->
  Option option
modify proxy f option = (alter go proxy option).option
  where
  go :: Data.Maybe.Maybe value' -> Data.Maybe.Maybe value
  go value' = case value' of
    Data.Maybe.Just value -> Data.Maybe.Just (f value)
    Data.Maybe.Nothing -> Data.Maybe.Nothing

-- | Changes a key with the given value to an option.
-- | The key must already exist in the option.
-- | If the key might not already exist in the option, `insert` should be used instead.
-- |
-- | E.g.
-- | ```PureScript
-- | someOption :: Option.Option ( foo :: Boolean, bar :: Int )
-- | someOption = Option.empty
-- |
-- | anotherOption :: Option.Option ( foo :: Boolean, bar :: Int )
-- | anotherOption = Option.set (Data.Symbol.SProxy :: _ "bar") 31 someOption
-- | ```
-- |
-- | The `proxy` can be anything so long as its type variable has kind `Symbol`.
-- |
-- | It will commonly be `Data.Symbol.SProxy`, but doesn't have to be.
set ::
  forall label option option' option'' proxy value value'.
  Data.Symbol.IsSymbol label =>
  Prim.Row.Cons label value' option'' option' =>
  Prim.Row.Cons label value option'' option =>
  proxy label ->
  value ->
  Option option' ->
  Option option
set proxy value = modify proxy go
  where
  go :: forall a. a -> value
  go _ = value

-- | Merges two options where no labels overlap.
disjointUnion
  :: forall option option' option''
   . Prim.Row.Union option option' option''
  => Prim.Row.Nub option'' option''
  => Option option
  -> Option option'
  -> Option option''
disjointUnion (Option option) (Option option') =
  Option $ Foreign.Object.union option option

-- | The expected `Record record` will have the same fields as the given `Option _` where each type is wrapped in a `Maybe`.
-- |
-- | E.g.
-- | ```PureScript
-- | someOption :: Option.Option ( foo :: Boolean, bar :: Int )
-- | someOption = Option.fromRecord { foo: true, bar: 31 }
-- |
-- | someRecord :: Record ( foo :: Data.Maybe.Maybe Boolean, bar :: Data.Maybe.Maybe Int )
-- | someRecord = Option.toRecord someOption
-- | ```
-- |
-- | This is an alias for `toRecord'` so the documentation is a bit clearer.
toRecord ::
  forall option record.
  ToRecord option record =>
  Option option ->
  Record record
toRecord = toRecord'

-- Sanity checks
-- These are in this module so things are always checked.
-- If a failure occurs in development, we can catch it early.
-- If a failure occurs in usage, it should be reported and addressed.
type User
  = Option ( username :: String, age :: Int )

-- does_not_type1 :: User
-- does_not_type1 = fromRecord { height: 10 }
-- does_not_type2 :: { age :: Data.Maybe.Maybe Int, username :: Data.Maybe.Maybe String }
-- does_not_type2 = toRecord empty
user :: User
user = empty

age :: Data.Maybe.Maybe Int
age = get (Data.Symbol.SProxy :: _ "age") user

user1 :: User
user1 = set (Data.Symbol.SProxy :: _ "age") 12 user

user2 :: Option ( username :: String, age :: Int, height :: Int )
user2 = insert (Data.Symbol.SProxy :: _ "height") 12 user

user3 :: Option ( username :: String, age :: Boolean )
user3 = set (Data.Symbol.SProxy :: _ "age") true user

user4 :: Option ( username :: String )
user4 = delete (Data.Symbol.SProxy :: _ "age") user

user5 :: Option ( username :: String, age :: Boolean )
user5 = modify (Data.Symbol.SProxy :: _ "age") (\_ -> true) user

user6 :: User
user6 = fromRecord {}

user7 :: User
user7 = fromRecord { age: 10 }

user8 :: { age :: Data.Maybe.Maybe Int, username :: Data.Maybe.Maybe String }
user8 = toRecord user
