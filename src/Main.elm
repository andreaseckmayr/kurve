module Main exposing (main)

import Browser
import Canvas exposing (bodyDrawingCmd, clearEverything, drawSpawnIfAndOnlyIf, headDrawingCmd)
import Config exposing (Config, PlayerConfig)
import Game exposing (GameState(..), MidRoundState, MidRoundStateVariant(..), SpawnState, checkIndividualPlayer, firstUpdateTick, modifyMidRoundState, modifyRound, prepareLiveRound, prepareReplayRound, recordUserInteraction)
import Html exposing (Html, canvas, div)
import Html.Attributes as Attr
import Input exposing (Button(..), ButtonDirection(..), inputSubscriptions, updatePressedButtons)
import Random
import Round exposing (Round, initialStateForReplaying, modifyAlive, modifyPlayers, roundIsOver)
import Set exposing (Set)
import Time
import Types.Tick as Tick exposing (Tick)
import Types.Tickrate as Tickrate
import Util exposing (isEven)


type alias Model =
    { pressedButtons : Set String
    , gameState : GameState
    , config : Config
    , playerConfigs : List PlayerConfig
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( { pressedButtons = Set.empty
      , gameState = Lobby (Random.initialSeed 1337)
      , config = Config.default
      , playerConfigs = Config.players
      }
    , Cmd.none
    )


startRound : Model -> MidRoundState -> ( Model, Cmd msg )
startRound model midRoundState =
    let
        ( gameState, cmd ) =
            newRoundGameStateAndCmd model.config midRoundState
    in
    ( { model | gameState = gameState }, cmd )


newRoundGameStateAndCmd : Config -> MidRoundState -> ( GameState, Cmd msg )
newRoundGameStateAndCmd config plannedMidRoundState =
    ( PreRound
        { playersLeft = Tuple.second plannedMidRoundState |> .players |> .alive
        , ticksLeft = config.spawn.numberOfFlickerTicks
        }
        plannedMidRoundState
    , clearEverything ( config.world.width, config.world.height )
    )


type Msg
    = GameTick Tick MidRoundState
    | ButtonUsed ButtonDirection Button
    | SpawnTick SpawnState MidRoundState


stepSpawnState : Config -> SpawnState -> ( MidRoundState -> GameState, Cmd msg )
stepSpawnState config { playersLeft, ticksLeft } =
    case playersLeft of
        [] ->
            -- All players have spawned.
            ( MidRound <| Tick.genesis, Cmd.none )

        spawning :: waiting ->
            let
                newSpawnState : SpawnState
                newSpawnState =
                    if ticksLeft == 0 then
                        { playersLeft = waiting, ticksLeft = config.spawn.numberOfFlickerTicks }

                    else
                        { playersLeft = spawning :: waiting, ticksLeft = ticksLeft - 1 }
            in
            ( PreRound newSpawnState, drawSpawnIfAndOnlyIf (isEven ticksLeft) spawning config.kurves.thickness )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg ({ pressedButtons } as model) =
    case msg of
        SpawnTick spawnState plannedMidRoundState ->
            stepSpawnState model.config spawnState
                |> Tuple.mapFirst (\makeGameState -> { model | gameState = makeGameState plannedMidRoundState })

        GameTick tick (( _, currentRound ) as midRoundState) ->
            let
                ( newPlayersGenerator, newOccupiedPixels, newColoredDrawingPositions ) =
                    List.foldr
                        (checkIndividualPlayer model.config tick)
                        ( Random.constant
                            { alive = [] -- We start with the empty list because the new one we'll create may not include all the players from the old one.
                            , dead = currentRound.players.dead -- Dead players, however, will not spring to life again.
                            }
                        , currentRound.occupiedPixels
                        , []
                        )
                        currentRound.players.alive

                ( newPlayers, newSeed ) =
                    Random.step newPlayersGenerator currentRound.seed

                newCurrentRound : Round
                newCurrentRound =
                    { players = newPlayers
                    , occupiedPixels = newOccupiedPixels
                    , history = currentRound.history
                    , seed = newSeed
                    }

                newGameState : GameState
                newGameState =
                    if roundIsOver newPlayers then
                        PostRound newCurrentRound

                    else
                        MidRound tick <| modifyRound (always newCurrentRound) midRoundState
            in
            ( { model | gameState = newGameState }
            , [ headDrawingCmd model.config.kurves.thickness newPlayers.alive
              , bodyDrawingCmd model.config.kurves.thickness newColoredDrawingPositions
              ]
                |> Cmd.batch
            )

        ButtonUsed Down button ->
            case model.gameState of
                Lobby seed ->
                    case button of
                        Key "Space" ->
                            startRound model <| prepareLiveRound model.config seed model.playerConfigs pressedButtons

                        _ ->
                            ( handleUserInteraction Down button model, Cmd.none )

                PostRound finishedRound ->
                    case button of
                        Key "KeyR" ->
                            startRound model <| prepareReplayRound model.config (initialStateForReplaying finishedRound)

                        Key "Space" ->
                            startRound model <| prepareLiveRound model.config finishedRound.seed model.playerConfigs pressedButtons

                        _ ->
                            ( handleUserInteraction Down button model, Cmd.none )

                _ ->
                    ( handleUserInteraction Down button model, Cmd.none )

        ButtonUsed Up key ->
            ( handleUserInteraction Up key model, Cmd.none )


handleUserInteraction : ButtonDirection -> Button -> Model -> Model
handleUserInteraction direction button model =
    let
        newPressedButtons : Set String
        newPressedButtons =
            updatePressedButtons direction button model.pressedButtons

        howToModifyRound : Round -> Round
        howToModifyRound =
            case model.gameState of
                MidRound lastTick ( Live, _ ) ->
                    recordInteractionBefore (Tick.succ lastTick)

                PreRound _ ( Live, _ ) ->
                    recordInteractionBefore firstUpdateTick

                _ ->
                    identity

        recordInteractionBefore : Tick -> Round -> Round
        recordInteractionBefore tick =
            modifyPlayers <| modifyAlive <| List.map (recordUserInteraction newPressedButtons tick)
    in
    { model
        | pressedButtons = newPressedButtons
        , gameState = modifyMidRoundState (modifyRound howToModifyRound) model.gameState
    }


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch <|
        (case model.gameState of
            Lobby _ ->
                Sub.none

            PostRound _ ->
                Sub.none

            PreRound spawnState plannedMidRoundState ->
                Time.every (1000 / model.config.spawn.flickerTicksPerSecond) (always <| SpawnTick spawnState plannedMidRoundState)

            MidRound lastTick midRoundState ->
                Time.every (1000 / Tickrate.toFloat model.config.kurves.tickrate) (always <| GameTick (Tick.succ lastTick) midRoundState)
        )
            :: inputSubscriptions ButtonUsed


view : Model -> Html Msg
view model =
    div
        [ Attr.id "wrapper"
        ]
        [ div
            [ Attr.id "border4"
            , Attr.class "border"
            ]
            [ div
                [ Attr.id "border3"
                , Attr.class "border"
                ]
                [ div
                    [ Attr.id "border2"
                    , Attr.class "border"
                    ]
                    [ div
                        [ Attr.id "border1"
                        , Attr.class "border"
                        ]
                        [ canvas
                            [ Attr.id "canvas_main"
                            , Attr.width 559
                            , Attr.height 480
                            ]
                            []
                        , canvas
                            [ Attr.id "canvas_overlay"
                            , Attr.width 559
                            , Attr.height 480
                            , Attr.class "overlay"
                            ]
                            []
                        , case model.gameState of
                            Lobby _ ->
                                lobby

                            _ ->
                                Html.text ""
                        ]
                    ]
                ]
            ]
        ]


lobby : Html msg
lobby =
    div
        [ Attr.id "lobby"
        ]
        [ Html.text "Press Space to start" ]


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }