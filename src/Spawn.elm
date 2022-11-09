module Spawn exposing (generateHoleSize, generateHoleSpacing, generatePlayers)

import Config exposing (Config, HoleConfig, KurveConfig, PlayerConfig, SpawnConfig, WorldConfig)
import Input exposing (toStringSetControls)
import Random
import Random.Extra as Random
import Types.Angle exposing (Angle(..))
import Types.Distance as Distance exposing (Distance(..))
import Types.Player as Player exposing (Player)
import Types.Radius as Radius exposing (Radius(..))
import Types.Thickness as Thickness exposing (Thickness(..))
import World exposing (Position, distanceToTicks)


generatePlayers : Config -> Random.Generator (List Player)
generatePlayers config =
    let
        numberOfPlayers =
            List.length config.players

        generateNewAndPrepend : Config.PlayerConfig -> List Player -> Random.Generator (List Player)
        generateNewAndPrepend playerConfig precedingPlayers =
            generatePlayer config numberOfPlayers (List.map .position precedingPlayers) playerConfig
                |> Random.map (\player -> player :: precedingPlayers)

        generateReversedPlayers =
            List.foldl
                (Random.andThen << generateNewAndPrepend)
                (Random.constant [])
                config.players
    in
    generateReversedPlayers |> Random.map List.reverse


isSafeNewPosition : Config -> Int -> List Position -> Position -> Bool
isSafeNewPosition config numberOfPlayers existingPositions newPosition =
    List.all (not << isTooCloseFor numberOfPlayers config newPosition) existingPositions


isTooCloseFor : Int -> Config -> Position -> Position -> Bool
isTooCloseFor numberOfPlayers config point1 point2 =
    let
        desiredMinimumDistance =
            toFloat (Thickness.toInt config.kurves.thickness) + Radius.toFloat config.kurves.turningRadius * config.spawn.desiredMinimumDistanceTurningRadiusFactor

        ( ( left, top ), ( right, bottom ) ) =
            spawnArea config.spawn config.world

        availableArea =
            (right - left) * (bottom - top)

        -- Derived from:
        -- audacity × total available area > number of players × ( max allowed minimum distance / 2 )² × pi
        maxAllowedMinimumDistance =
            2 * sqrt (config.spawn.protectionAudacity * availableArea / (toFloat numberOfPlayers * pi))
    in
    Distance.toFloat (distanceBetween point1 point2) < min desiredMinimumDistance maxAllowedMinimumDistance


distanceBetween : Position -> Position -> Distance
distanceBetween ( x1, y1 ) ( x2, y2 ) =
    Distance <| sqrt ((x2 - x1) ^ 2 + (y2 - y1) ^ 2)


generatePlayer : Config -> Int -> List Position -> PlayerConfig -> Random.Generator Player
generatePlayer config numberOfPlayers existingPositions playerConfig =
    let
        safeSpawnPosition =
            generateSpawnPosition config.spawn config.world |> Random.filter (isSafeNewPosition config numberOfPlayers existingPositions)
    in
    Random.map3
        (\generatedPosition generatedAngle generatedHoleStatus ->
            { color = playerConfig.color
            , controls = toStringSetControls playerConfig.controls
            , position = generatedPosition
            , direction = generatedAngle
            , holeStatus = generatedHoleStatus
            }
        )
        safeSpawnPosition
        (generateSpawnAngle config.spawn.angleInterval)
        (generateInitialHoleStatus config.kurves)


spawnArea : SpawnConfig -> WorldConfig -> ( Position, Position )
spawnArea { margin } { width, height } =
    let
        topLeft =
            ( margin
            , margin
            )

        bottomRight =
            ( toFloat width - margin
            , toFloat height - margin
            )
    in
    ( topLeft, bottomRight )


generateSpawnPosition : SpawnConfig -> WorldConfig -> Random.Generator Position
generateSpawnPosition spawnConfig worldConfig =
    let
        ( ( left, top ), ( right, bottom ) ) =
            spawnArea spawnConfig worldConfig
    in
    Random.pair (Random.float left right) (Random.float top bottom)


generateSpawnAngle : ( Float, Float ) -> Random.Generator Angle
generateSpawnAngle ( min, max ) =
    Random.float min max |> Random.map Angle


generateHoleSpacing : HoleConfig -> Random.Generator Distance
generateHoleSpacing holeConfig =
    Distance.generate holeConfig.minInterval holeConfig.maxInterval


generateHoleSize : HoleConfig -> Random.Generator Distance
generateHoleSize holeConfig =
    Distance.generate holeConfig.minSize holeConfig.maxSize


generateInitialHoleStatus : KurveConfig -> Random.Generator Player.HoleStatus
generateInitialHoleStatus { tickrate, speed, holes } =
    generateHoleSpacing holes |> Random.map (distanceToTicks tickrate speed >> Player.Unholy)
