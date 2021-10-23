port module Main exposing (main)

import Platform exposing (worker)
import Set exposing (Set)
import Time


port render : { x : Int, y : Int } -> Cmd msg


port onKeydown : (String -> msg) -> Sub msg


port onKeyup : (String -> msg) -> Sub msg


tickrate : Float
tickrate =
    60


type alias Model =
    { x : Float
    , y : Float
    , direction : Float
    , pressedKeys : Set String
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( { x = 300
      , y = 300
      , direction = 0.5
      , pressedKeys = Set.empty
      }
    , Cmd.none
    )


type Msg
    = Tick Time.Posix
    | KeyWasPressed String
    | KeyWasReleased String


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        Tick _ ->
            let
                theta =
                    1

                angleChange =
                    0.1

                newDirection =
                    if Set.member "m" model.pressedKeys then
                        model.direction + angleChange

                    else if Set.member "," model.pressedKeys then
                        model.direction - angleChange

                    else
                        model.direction

                newModel =
                    { model
                        | x = model.x + theta * cos newDirection
                        , y = model.y - theta * sin newDirection
                        , direction = newDirection
                    }
            in
            ( newModel
            , render (integerCoordinates { x = newModel.x, y = newModel.y })
            )

        KeyWasPressed key ->
            ( { model | pressedKeys = Set.insert key model.pressedKeys }
            , Cmd.none
            )

        KeyWasReleased key ->
            ( { model | pressedKeys = Set.remove key model.pressedKeys }
            , Cmd.none
            )


integerCoordinates : { x : Float, y : Float } -> { x : Int, y : Int }
integerCoordinates coords =
    { x = round coords.x
    , y = round coords.y
    }


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ Time.every (1000 / tickrate) Tick
        , onKeydown KeyWasPressed
        , onKeyup KeyWasReleased
        ]


main =
    worker
        { init = init
        , update = update
        , subscriptions = subscriptions
        }
