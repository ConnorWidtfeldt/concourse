module ResourceTests exposing (all)

import Application.Application as Application
import Application.Models exposing (Session)
import Assets
import Common exposing (defineHoverBehaviour, queryView)
import Concourse
import Concourse.BuildStatus exposing (BuildStatus(..))
import Concourse.Pagination exposing (Direction(..))
import DashboardTests
    exposing
        ( almostBlack
        , darkGrey
        , iconSelector
        , middleGrey
        )
import Data
import Dict
import Expect exposing (..)
import HoverState
import Html.Attributes as Attr
import Http
import Keyboard
import Message.Callback as Callback exposing (Callback(..))
import Message.Effects as Effects
import Message.Message exposing (DomID(..), Message(..))
import Message.Subscription as Subscription
    exposing
        ( Delivery(..)
        , Interval(..)
        )
import Message.TopLevelMessage as Msgs
import Pinned exposing (VersionPinState(..))
import RemoteData
import Resource.Models as Models
import Resource.Resource as Resource
import Routes
import ScreenSize
import Set
import Test exposing (..)
import Test.Html.Event as Event
import Test.Html.Query as Query
import Test.Html.Selector
    exposing
        ( Selector
        , attribute
        , class
        , containing
        , id
        , style
        , tag
        , text
        )
import Time
import Url
import UserState exposing (UserState(..))


commentButtonBlue : String
commentButtonBlue =
    "#196ac8"


teamName : String
teamName =
    "some-team"


pipelineName : String
pipelineName =
    "some-pipeline"


resourceName : String
resourceName =
    "some-resource"


resourceIcon : String
resourceIcon =
    "some-icon"


versionID : Models.VersionId
versionID =
    { teamName = teamName
    , pipelineName = pipelineName
    , resourceName = resourceName
    , versionID = 1
    }


otherVersionID : Models.VersionId
otherVersionID =
    { teamName = teamName
    , pipelineName = pipelineName
    , resourceName = resourceName
    , versionID = 2
    }


disabledVersionID : Models.VersionId
disabledVersionID =
    { teamName = teamName
    , pipelineName = pipelineName
    , resourceName = resourceName
    , versionID = 3
    }


version : String
version =
    "v1"


otherVersion : String
otherVersion =
    "v2"


disabledVersion : String
disabledVersion =
    "v3"


purpleHex : String
purpleHex =
    "#5c3bd1"


fadedBlackHex : String
fadedBlackHex =
    "#1e1d1d80"


almostWhiteHex : String
almostWhiteHex =
    "#e6e7e8"


lightGreyHex : String
lightGreyHex =
    "#3d3c3c"


tooltipGreyHex : String
tooltipGreyHex =
    "#9b9b9b"


darkGreyHex : String
darkGreyHex =
    "#1e1d1d"


failureRed : String
failureRed =
    "#ed4b35"


badResponse : Result Http.Error ()
badResponse =
    Err <|
        Http.BadStatus
            { url = ""
            , status =
                { code = 500
                , message = "server error"
                }
            , headers = Dict.empty
            , body = ""
            }


all : Test
all =
    describe "resource page"
        [ describe "when logging out" <|
            let
                loggingOut : () -> ( Application.Model, List Effects.Effect )
                loggingOut _ =
                    init
                        |> Application.handleCallback
                            (Callback.UserFetched <|
                                Ok
                                    { id = "test"
                                    , userName = "test"
                                    , name = "test"
                                    , email = "test"
                                    , isAdmin = False
                                    , teams =
                                        Dict.fromList
                                            [ ( teamName, [ "member" ] )
                                            ]
                                    }
                            )
                        |> Tuple.first
                        |> Application.handleCallback
                            (Callback.LoggedOut (Ok ()))
            in
            [ test "updates top bar state" <|
                loggingOut
                    >> Tuple.first
                    >> queryView
                    >> Query.find [ id "top-bar-app" ]
                    >> Query.children []
                    >> Query.index -1
                    >> Query.has [ text "login" ]
            , test "redirects to dashboard" <|
                loggingOut
                    >> Tuple.second
                    >> Expect.equal
                        [ Effects.NavigateTo <|
                            Routes.toString <|
                                Routes.Dashboard <|
                                    Routes.Normal Nothing
                        ]
            ]
        , test "has title with resource name" <|
            \_ ->
                init
                    |> Application.view
                    |> .title
                    |> Expect.equal "some-resource - Concourse"
        , test "fetches time zone on page load" <|
            \_ ->
                Application.init
                    { turbulenceImgSrc = ""
                    , notFoundImgSrc = "notfound.svg"
                    , csrfToken = "csrf_token"
                    , authToken = ""
                    , pipelineRunningKeyframes = "pipeline-running"
                    }
                    { protocol = Url.Http
                    , host = ""
                    , port_ = Nothing
                    , path =
                        "/teams/"
                            ++ teamName
                            ++ "/pipelines/"
                            ++ pipelineName
                            ++ "/resources/"
                            ++ resourceName
                    , query = Nothing
                    , fragment = Nothing
                    }
                    |> Tuple.second
                    |> Common.contains Effects.GetCurrentTimeZone
        , test "subscribes to the five second interval" <|
            \_ ->
                init
                    |> Application.subscriptions
                    |> Common.contains (Subscription.OnClockTick FiveSeconds)
        , test "autorefreshes resource and versions every five seconds" <|
            \_ ->
                init
                    |> Application.update
                        (Msgs.DeliveryReceived
                            (ClockTicked FiveSeconds <|
                                Time.millisToPosix 0
                            )
                        )
                    |> Tuple.second
                    |> Expect.all
                        [ Common.contains
                            (Effects.FetchResource
                                { resourceName = resourceName
                                , pipelineName = pipelineName
                                , teamName = teamName
                                }
                            )
                        , Common.contains
                            (Effects.FetchVersionedResources
                                { resourceName = resourceName
                                , pipelineName = pipelineName
                                , teamName = teamName
                                }
                                Nothing
                            )
                        ]
        , test "autorefresh respects expanded state" <|
            \_ ->
                init
                    |> givenResourceIsNotPinned
                    |> givenVersionsWithoutPagination
                    |> update
                        (Message.Message.Click <|
                            Message.Message.VersionHeader versionID
                        )
                    |> Tuple.first
                    |> givenVersionsWithoutPagination
                    |> queryView
                    |> Query.find (versionSelector version)
                    |> Query.has [ text "metadata" ]
        , test "autorefresh respects 'Inputs To'" <|
            \_ ->
                init
                    |> givenResourceIsNotPinned
                    |> givenVersionsWithoutPagination
                    |> update
                        (Message.Message.Click <|
                            Message.Message.VersionHeader versionID
                        )
                    |> Tuple.first
                    |> Application.handleCallback
                        (Callback.InputToFetched
                            (Ok
                                ( versionID
                                , [ { id = 0
                                    , name = "some-build"
                                    , job =
                                        Just
                                            { teamName = teamName
                                            , pipelineName = pipelineName
                                            , jobName = "some-job"
                                            }
                                    , status = BuildStatusSucceeded
                                    , duration =
                                        { startedAt = Nothing
                                        , finishedAt = Nothing
                                        }
                                    , reapTime = Nothing
                                    }
                                  ]
                                )
                            )
                        )
                    |> Tuple.first
                    |> givenVersionsWithoutPagination
                    |> queryView
                    |> Query.find (versionSelector version)
                    |> Query.has [ text "some-build" ]
        , test "autorefresh respects 'Outputs Of'" <|
            \_ ->
                init
                    |> givenResourceIsNotPinned
                    |> givenVersionsWithoutPagination
                    |> update
                        (Message.Message.Click <|
                            Message.Message.VersionHeader versionID
                        )
                    |> Tuple.first
                    |> Application.handleCallback
                        (Callback.OutputOfFetched
                            (Ok
                                ( versionID
                                , [ { id = 0
                                    , name = "some-build"
                                    , job =
                                        Just
                                            { teamName = teamName
                                            , pipelineName = pipelineName
                                            , jobName = "some-job"
                                            }
                                    , status = BuildStatusSucceeded
                                    , duration =
                                        { startedAt = Nothing
                                        , finishedAt = Nothing
                                        }
                                    , reapTime = Nothing
                                    }
                                  ]
                                )
                            )
                        )
                    |> Tuple.first
                    |> givenVersionsWithoutPagination
                    |> queryView
                    |> Query.find (versionSelector version)
                    |> Query.has [ text "some-build" ]
        , describe "page header with icon" <|
            let
                pageHeader =
                    init
                        |> givenResourceHasIcon
                        |> queryView
                        |> Query.find [ id "page-header" ]
            in
            [ describe "resource name"
                [ test "on the left is the resource name" <|
                    \_ ->
                        pageHeader
                            |> Query.children []
                            |> Query.index 0
                            |> Query.has [ tag "svg", text resourceName, tag "h1" ]
                ]
            , describe "resource icon"
                [ test "on the left is the resource icon" <|
                    \_ ->
                        pageHeader
                            |> Query.children []
                            |> Query.index 0
                            |> Query.has [ tag "svg" ]
                ]
            ]
        , describe "page header" <|
            let
                pageHeader =
                    init
                        |> givenResourceIsNotPinned
                        |> queryView
                        |> Query.find [ id "page-header" ]
            in
            [ test "has dark grey background" <|
                \_ ->
                    pageHeader
                        |> Query.has
                            [ style "height" "60px"
                            , style "background-color" "#2a2929"
                            ]
            , test "lays out contents horizontally, stretching them vertically" <|
                \_ ->
                    pageHeader
                        |> Query.has
                            [ style "display" "flex"
                            , style "align-items" "stretch"
                            ]
            , describe "resource name"
                [ test "on the left is the resource name" <|
                    \_ ->
                        pageHeader
                            |> Query.children []
                            |> Query.index 0
                            |> Query.has [ text resourceName, tag "h1" ]
                , test "the text is large and vertically centred" <|
                    \_ ->
                        pageHeader
                            |> Query.children []
                            |> Query.index 0
                            |> Query.has
                                [ style "font-weight" "700"
                                , style "margin-left" "18px"
                                , style "display" "flex"
                                , style "align-items" "center"
                                , style "justify-content" "center"
                                ]
                ]
            , describe "last checked"
                [ test "last checked view is second from left" <|
                    \_ ->
                        init
                            |> givenResourceIsNotPinned
                            |> Application.update
                                (Msgs.DeliveryReceived <|
                                    Subscription.ClockTicked Subscription.OneSecond <|
                                        Time.millisToPosix 1000
                                )
                            |> Tuple.first
                            |> queryView
                            |> Query.find [ id "page-header" ]
                            |> Query.children []
                            |> Query.index 1
                            |> Query.has [ text "1s ago" ]
                , test "last checked view displays its contents centred" <|
                    \_ ->
                        init
                            |> givenResourceIsNotPinned
                            |> Application.update
                                (Msgs.DeliveryReceived <|
                                    Subscription.ClockTicked Subscription.OneSecond <|
                                        Time.millisToPosix 1000
                                )
                            |> Tuple.first
                            |> queryView
                            |> Query.find [ id "page-header" ]
                            |> Query.children []
                            |> Query.index 1
                            |> Query.has
                                [ style "display" "flex"
                                , style "align-items" "center"
                                , style "justify-content" "center"
                                , style "margin-left" "24px"
                                ]
                ]
            , describe "pagination"
                [ test "pagination is last on the right" <|
                    \_ ->
                        init
                            |> givenResourceIsNotPinned
                            |> givenVersionsWithPagination
                            |> queryView
                            |> Query.find [ id "page-header" ]
                            |> Query.children []
                            |> Query.index -1
                            |> Query.has [ id "pagination" ]
                , test "pagination displays the pages horizontally" <|
                    \_ ->
                        init
                            |> givenResourceIsNotPinned
                            |> givenVersionsWithPagination
                            |> queryView
                            |> Query.find [ id "pagination" ]
                            |> Query.has
                                [ style "display" "flex"
                                , style "align-items" "stretch"
                                ]
                , describe "pagination chevrons"
                    [ test "with no pages" <|
                        \_ ->
                            init
                                |> givenResourceIsNotPinned
                                |> givenVersionsWithoutPagination
                                |> queryView
                                |> Query.find [ id "pagination" ]
                                |> Query.children []
                                |> Expect.all
                                    [ Query.index 0
                                        >> Query.has
                                            [ style "padding" "5px"
                                            , style "display" "flex"
                                            , style "align-items" "center"
                                            , style "border-left" <|
                                                "1px solid "
                                                    ++ middleGrey
                                            , containing
                                                (iconSelector
                                                    { image = Assets.ChevronLeft
                                                    , size = "24px"
                                                    }
                                                    ++ [ style "padding" "5px"
                                                       , style "opacity" "0.5"
                                                       ]
                                                )
                                            ]
                                    , Query.index 1
                                        >> Query.has
                                            [ style "padding" "5px"
                                            , style "display" "flex"
                                            , style "align-items" "center"
                                            , style "border-left" <|
                                                "1px solid "
                                                    ++ middleGrey
                                            , containing
                                                (iconSelector
                                                    { image = Assets.ChevronRight
                                                    , size = "24px"
                                                    }
                                                    ++ [ style "padding" "5px"
                                                       , style "opacity" "0.5"
                                                       ]
                                                )
                                            ]
                                    ]
                    , defineHoverBehaviour <|
                        let
                            urlPath =
                                "/teams/some-team/pipelines/some-pipeline/resources/some-resource?since=1&limit=1"
                        in
                        { name = "left pagination chevron with previous page"
                        , setup =
                            init
                                |> givenResourceIsNotPinned
                                |> givenVersionsWithPagination
                        , query =
                            queryView
                                >> Query.find [ id "pagination" ]
                                >> Query.children []
                                >> Query.index 0
                        , unhoveredSelector =
                            { description = "white left chevron"
                            , selector =
                                [ style "padding" "5px"
                                , style "display" "flex"
                                , style "align-items" "center"
                                , style "border-left" <|
                                    "1px solid "
                                        ++ middleGrey
                                , containing
                                    (iconSelector
                                        { image = Assets.ChevronLeft
                                        , size = "24px"
                                        }
                                        ++ [ style "padding" "5px"
                                           , style "opacity" "1"
                                           , attribute <| Attr.href urlPath
                                           ]
                                    )
                                ]
                            }
                        , hoveredSelector =
                            { description =
                                "left chevron with light grey circular bg"
                            , selector =
                                [ style "padding" "5px"
                                , style "display" "flex"
                                , style "align-items" "center"
                                , style "border-left" <|
                                    "1px solid "
                                        ++ middleGrey
                                , containing
                                    (iconSelector
                                        { image = Assets.ChevronLeft
                                        , size = "24px"
                                        }
                                        ++ [ style "padding" "5px"
                                           , style "opacity" "1"
                                           , style "border-radius" "50%"
                                           , style "background-color" <|
                                                "#504b4b"
                                           , attribute <| Attr.href urlPath
                                           ]
                                    )
                                ]
                            }
                        , hoverable = Message.Message.PreviousPageButton
                        }
                    ]
                ]
            ]
        , describe "page body" <|
            [ test "has 10px padding" <|
                \_ ->
                    init
                        |> givenResourceIsNotPinned
                        |> queryView
                        |> Query.find [ id "body" ]
                        |> Query.has [ style "padding" "10px" ]
            , test "scrolls independently" <|
                \_ ->
                    init
                        |> givenResourceIsNotPinned
                        |> queryView
                        |> Query.find [ id "body" ]
                        |> Query.has [ style "overflow-y" "auto" ]
            , test "fills vertical space" <|
                \_ ->
                    init
                        |> givenResourceIsNotPinned
                        |> queryView
                        |> Query.find [ id "body" ]
                        |> Query.has [ style "flex-grow" "1" ]
            ]
        , describe "checkboxes" <|
            let
                checkIcon =
                    Assets.backgroundImage <|
                        Just Assets.CheckmarkIcon
            in
            [ test "there is a checkbox for every version" <|
                \_ ->
                    init
                        |> givenResourceIsNotPinned
                        |> givenVersionsWithoutPagination
                        |> queryView
                        |> Query.find [ class "resource-versions" ]
                        |> Query.findAll anyVersionSelector
                        |> Query.each hasCheckbox
            , test "there is a pointer cursor for every checkbox" <|
                \_ ->
                    init
                        |> givenResourceIsNotPinned
                        |> givenVersionsWithoutPagination
                        |> queryView
                        |> Query.find [ class "resource-versions" ]
                        |> Query.findAll anyVersionSelector
                        |> Query.each
                            (Query.find checkboxSelector
                                >> Query.has pointerCursor
                            )
            , test "enabled versions have checkmarks" <|
                \_ ->
                    init
                        |> givenResourcePinnedStatically
                        |> givenVersionsWithoutPagination
                        |> queryView
                        |> Expect.all
                            [ Query.find (versionSelector version)
                                >> Query.find checkboxSelector
                                >> Query.has
                                    [ style "background-image" checkIcon ]
                            , Query.find (versionSelector otherVersion)
                                >> Query.find checkboxSelector
                                >> Query.has
                                    [ style "background-image" checkIcon ]
                            ]
            , test "disabled versions do not have checkmarks" <|
                \_ ->
                    init
                        |> givenResourcePinnedStatically
                        |> givenVersionsWithoutPagination
                        |> queryView
                        |> Query.find (versionSelector disabledVersion)
                        |> Query.find checkboxSelector
                        |> Query.hasNot [ style "background-image" checkIcon ]
            , test "clicking the checkbox on an enabled version triggers a ToggleVersion msg" <|
                \_ ->
                    init
                        |> givenResourcePinnedStatically
                        |> givenVersionsWithoutPagination
                        |> queryView
                        |> Query.find (versionSelector version)
                        |> Query.find checkboxSelector
                        |> Event.simulate Event.click
                        |> Event.expect
                            (Msgs.Update <|
                                Message.Message.Click <|
                                    Message.Message.VersionToggle
                                        versionID
                            )
            , test "receiving a (ToggleVersion Disable) msg causes the relevant checkbox to go into a transition state" <|
                \_ ->
                    init
                        |> givenResourcePinnedStatically
                        |> givenVersionsWithoutPagination
                        |> clickToDisable versionID
                        |> queryView
                        |> Query.find (versionSelector version)
                        |> Query.find checkboxSelector
                        |> checkboxHasTransitionState
            , test "autorefreshing after receiving a ToggleVersion msg causes the relevant checkbox to stay in a transition state" <|
                \_ ->
                    init
                        |> givenResourcePinnedStatically
                        |> givenVersionsWithoutPagination
                        |> clickToDisable versionID
                        |> givenVersionsWithoutPagination
                        |> queryView
                        |> Query.find (versionSelector version)
                        |> Query.find checkboxSelector
                        |> checkboxHasTransitionState
            , test "receiving a successful VersionToggled msg causes the relevant checkbox to appear unchecked" <|
                \_ ->
                    init
                        |> givenResourcePinnedStatically
                        |> givenVersionsWithoutPagination
                        |> clickToDisable versionID
                        |> Application.handleCallback (Callback.VersionToggled Message.Message.Disable versionID (Ok ()))
                        |> Tuple.first
                        |> queryView
                        |> Query.find (versionSelector version)
                        |> versionHasDisabledState
            , test "receiving an error on VersionToggled msg causes the checkbox to go back to its checked state" <|
                \_ ->
                    init
                        |> givenResourcePinnedStatically
                        |> givenVersionsWithoutPagination
                        |> clickToDisable versionID
                        |> Application.handleCallback (Callback.VersionToggled Message.Message.Disable versionID badResponse)
                        |> Tuple.first
                        |> queryView
                        |> Query.find (versionSelector version)
                        |> Query.find checkboxSelector
                        |> checkboxHasEnabledState
            , test "clicking the checkbox on a disabled version triggers a ToggleVersion msg" <|
                \_ ->
                    init
                        |> givenResourcePinnedStatically
                        |> givenVersionsWithoutPagination
                        |> queryView
                        |> Query.find (versionSelector disabledVersion)
                        |> Query.find checkboxSelector
                        |> Event.simulate Event.click
                        |> Event.expect
                            (Msgs.Update <|
                                Message.Message.Click <|
                                    Message.Message.VersionToggle
                                        disabledVersionID
                            )
            , test "receiving a (ToggleVersion Enable) msg causes the relevant checkbox to go into a transition state" <|
                \_ ->
                    init
                        |> givenResourcePinnedStatically
                        |> givenVersionsWithoutPagination
                        |> Application.update
                            (Msgs.Update <|
                                Message.Message.Click <|
                                    Message.Message.VersionToggle
                                        disabledVersionID
                            )
                        |> Tuple.first
                        |> queryView
                        |> Query.find (versionSelector disabledVersion)
                        |> Query.find checkboxSelector
                        |> checkboxHasTransitionState
            , test "receiving a successful VersionToggled msg causes the relevant checkbox to appear checked" <|
                \_ ->
                    init
                        |> givenResourcePinnedStatically
                        |> givenVersionsWithoutPagination
                        |> Application.update
                            (Msgs.Update <|
                                Message.Message.Click <|
                                    Message.Message.VersionToggle
                                        disabledVersionID
                            )
                        |> Tuple.first
                        |> Application.handleCallback
                            (Callback.VersionToggled
                                Message.Message.Enable
                                disabledVersionID
                                (Ok ())
                            )
                        |> Tuple.first
                        |> queryView
                        |> Query.find (versionSelector disabledVersion)
                        |> Query.find checkboxSelector
                        |> checkboxHasEnabledState
            , test "receiving a failing VersionToggled msg causes the relevant checkbox to return to its unchecked state" <|
                \_ ->
                    init
                        |> givenResourcePinnedStatically
                        |> givenVersionsWithoutPagination
                        |> Application.update
                            (Msgs.Update <|
                                Message.Message.Click <|
                                    Message.Message.VersionToggle
                                        disabledVersionID
                            )
                        |> Tuple.first
                        |> Application.handleCallback
                            (Callback.VersionToggled
                                Message.Message.Enable
                                disabledVersionID
                                badResponse
                            )
                        |> Tuple.first
                        |> queryView
                        |> Query.find (versionSelector disabledVersion)
                        |> Query.find checkboxSelector
                        |> checkboxHasDisabledState
            ]
        , describe "given resource is pinned statically"
            [ describe "pin bar"
                [ test "then pinned version is visible in pin bar" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> queryView
                            |> Query.find [ id "pin-bar" ]
                            |> Query.has [ text version ]
                , test "pin icon on pin bar has default cursor" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> queryView
                            |> Query.find [ id "pin-icon" ]
                            |> Query.has defaultCursor
                , test "clicking pin icon on pin bar does nothing" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> queryView
                            |> Query.find [ id "pin-icon" ]
                            |> Event.simulate Event.click
                            |> Event.toResult
                            |> Expect.err
                , test "there is a bit of space betwen the pin icon and the version in the pin bar" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> queryView
                            |> Query.find [ id "pin-icon" ]
                            |> Query.has
                                [ style "margin-right" "10px" ]
                , test "mousing over pin icon does nothing" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> queryView
                            |> Query.find [ id "pin-icon" ]
                            |> Event.simulate Event.mouseEnter
                            |> Event.toResult
                            |> Expect.err
                , test "pin button on pinned version has a purple outline" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> givenVersionsWithoutPagination
                            |> queryView
                            |> Query.find (versionSelector version)
                            |> Query.find pinButtonSelector
                            |> Query.has purpleOutlineSelector
                , test "checkbox on pinned version has a purple outline" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> givenVersionsWithoutPagination
                            |> queryView
                            |> Query.find (versionSelector version)
                            |> Query.find checkboxSelector
                            |> Query.has purpleOutlineSelector
                , test "all pin buttons have default cursor" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> givenVersionsWithoutPagination
                            |> queryView
                            |> Query.find [ class "resource-versions" ]
                            |> Query.findAll anyVersionSelector
                            |> Query.each
                                (Query.find pinButtonSelector
                                    >> Query.has defaultCursor
                                )
                , test "version header on pinned version has a purple outline" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> givenVersionsWithoutPagination
                            |> queryView
                            |> Query.find (versionSelector version)
                            |> findLast [ tag "div", containing [ text version ] ]
                            |> Query.has purpleOutlineSelector
                , test "mousing over pin bar sends TogglePinBarTooltip message" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> queryView
                            |> Query.find [ id "pin-bar" ]
                            |> Event.simulate Event.mouseEnter
                            |> Event.expect
                                (Msgs.Update <| Message.Message.Hover <| Just Message.Message.PinBar)
                , test "TogglePinBarTooltip causes tooltip to appear" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> hoverOverPinBar
                            |> queryView
                            |> Query.has pinBarTooltipSelector
                , test "pin bar tooltip has text 'pinned in pipeline config'" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> hoverOverPinBar
                            |> queryView
                            |> Query.find pinBarTooltipSelector
                            |> Query.has [ text "pinned in pipeline config" ]
                , test "pin bar tooltip is positioned above and near the left of the pin bar" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> hoverOverPinBar
                            |> queryView
                            |> Query.find pinBarTooltipSelector
                            |> Query.has
                                [ style "position" "absolute"
                                , style "top" "-10px"
                                , style "left" "30px"
                                ]
                , test "pin bar tooltip is light grey" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> hoverOverPinBar
                            |> queryView
                            |> Query.find pinBarTooltipSelector
                            |> Query.has
                                [ style "background-color" tooltipGreyHex ]
                , test "pin bar tooltip has a bit of padding around text" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> hoverOverPinBar
                            |> queryView
                            |> Query.find pinBarTooltipSelector
                            |> Query.has
                                [ style "padding" "5px" ]
                , test "pin bar tooltip appears above other elements in the DOM" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> hoverOverPinBar
                            |> queryView
                            |> Query.find pinBarTooltipSelector
                            |> Query.has
                                [ style "z-index" "2" ]
                , test "mousing out of pin bar sends Hover Nothing message" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> hoverOverPinBar
                            |> queryView
                            |> Query.find [ id "pin-bar" ]
                            |> Event.simulate Event.mouseLeave
                            |> Event.expect
                                (Msgs.Update <| Message.Message.Hover Nothing)
                , test "when mousing off pin bar, tooltip disappears" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> hoverOverPinBar
                            |> update (Message.Message.Hover Nothing)
                            |> Tuple.first
                            |> queryView
                            |> Query.hasNot pinBarTooltipSelector
                ]
            , describe "per-version pin buttons"
                [ test "unpinned versions are lower opacity" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> givenVersionsWithoutPagination
                            |> queryView
                            |> Query.find (versionSelector otherVersion)
                            |> Query.has [ style "opacity" "0.5" ]
                , test "mousing over the pinned version's pin button sends ToggleVersionTooltip" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> givenVersionsWithoutPagination
                            |> queryView
                            |> Query.find (versionSelector version)
                            |> Query.find pinButtonSelector
                            |> Event.simulate Event.mouseOver
                            |> Event.expect
                                (Msgs.Update <|
                                    Message.Message.Hover <|
                                        Just <|
                                            Message.Message.PinButton versionID
                                )
                , test "mousing over an unpinned version's pin button doesn't send any msg" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> givenVersionsWithoutPagination
                            |> queryView
                            |> Query.find (versionSelector otherVersion)
                            |> Query.find pinButtonSelector
                            |> Event.simulate Event.mouseOver
                            |> Event.toResult
                            |> Expect.err
                , test "shows tooltip on the pinned version's pin button on ToggleVersionTooltip" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> givenVersionsWithoutPagination
                            |> hoverOverPinButton
                            |> queryView
                            |> Query.find (versionSelector version)
                            |> Query.has versionTooltipSelector
                , test "keeps tooltip on the pinned version's pin button on autorefresh" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> givenVersionsWithoutPagination
                            |> hoverOverPinButton
                            |> givenVersionsWithoutPagination
                            |> queryView
                            |> Query.find (versionSelector version)
                            |> Query.has versionTooltipSelector
                , test "mousing off the pinned version's pin button sends Hover Nothing" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> givenVersionsWithoutPagination
                            |> hoverOverPinButton
                            |> queryView
                            |> Query.find (versionSelector version)
                            |> Query.find pinButtonSelector
                            |> Event.simulate Event.mouseOut
                            |> Event.expect
                                (Msgs.Update <| Message.Message.Hover Nothing)
                , test "mousing off an unpinned version's pin button doesn't send any msg" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> givenVersionsWithoutPagination
                            |> hoverOverPinButton
                            |> queryView
                            |> Query.find (versionSelector otherVersion)
                            |> Query.find pinButtonSelector
                            |> Event.simulate Event.mouseOut
                            |> Event.toResult
                            |> Expect.err
                , test "hides tooltip on the pinned version's pin button on ToggleVersionTooltip" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> givenVersionsWithoutPagination
                            |> hoverOverPinButton
                            |> update (Message.Message.Hover Nothing)
                            |> Tuple.first
                            |> queryView
                            |> Query.find (versionSelector version)
                            |> Query.hasNot versionTooltipSelector
                , test "clicking on pin button on pinned version doesn't send any msg" <|
                    \_ ->
                        init
                            |> givenResourcePinnedStatically
                            |> givenVersionsWithoutPagination
                            |> clickToUnpin
                            |> queryView
                            |> Query.find (versionSelector version)
                            |> Query.find pinButtonSelector
                            |> Event.simulate Event.click
                            |> Event.toResult
                            |> Expect.err
                , test "all pin buttons have dark background" <|
                    \_ ->
                        init
                            |> givenResourceIsNotPinned
                            |> givenVersionsWithoutPagination
                            |> queryView
                            |> Query.find [ class "resource-versions" ]
                            |> Query.findAll anyVersionSelector
                            |> Query.each
                                (Query.find pinButtonSelector
                                    >> Query.has [ style "background-color" "#1e1d1d" ]
                                )
                ]
            ]
        , describe "given resource is pinned dynamically"
            [ describe "pin bar"
                [ test "when mousing over pin bar, tooltip does not appear" <|
                    \_ ->
                        init
                            |> givenResourcePinnedDynamically
                            |> queryView
                            |> Query.find [ id "pin-bar" ]
                            |> Event.simulate Event.mouseEnter
                            |> Event.toResult
                            |> Expect.err
                , test "pin bar has a white pin icon of size 25 px" <|
                    \_ ->
                        init
                            |> givenResourcePinnedDynamically
                            |> queryView
                            |> Query.find [ id "pin-bar" ]
                            |> Query.has
                                (iconSelector
                                    { size = "25px"
                                    , image = Assets.PinIconWhite
                                    }
                                )
                , test "pin icon on pin bar has a margin right of 10 px" <|
                    \_ ->
                        init
                            |> givenResourcePinnedDynamically
                            |> queryView
                            |> Query.find [ id "pin-icon" ]
                            |> Query.has [ style "margin-right" "10px" ]
                , test "pin icon on pin bar has pointer cursor" <|
                    \_ ->
                        init
                            |> givenResourcePinnedDynamically
                            |> queryView
                            |> Query.find [ id "pin-icon" ]
                            |> Query.has pointerCursor
                , test "clicking pin icon on bar triggers UnpinVersion msg" <|
                    \_ ->
                        init
                            |> givenResourcePinnedDynamically
                            |> queryView
                            |> Query.find [ id "pin-icon" ]
                            |> Event.simulate Event.click
                            |> Event.expect
                                (Msgs.Update <|
                                    Message.Message.Click Message.Message.PinIcon
                                )
                , test "mousing over pin icon triggers PinIconHover msg" <|
                    \_ ->
                        init
                            |> givenResourcePinnedDynamically
                            |> queryView
                            |> Query.find [ id "pin-icon" ]
                            |> Event.simulate Event.mouseEnter
                            |> Event.expect
                                (Msgs.Update <|
                                    Message.Message.Hover <|
                                        Just Message.Message.PinIcon
                                )
                , test "TogglePinIconHover msg causes pin icon to have dark background" <|
                    \_ ->
                        init
                            |> givenResourcePinnedDynamically
                            |> update
                                (Message.Message.Hover <|
                                    Just Message.Message.PinIcon
                                )
                            |> Tuple.first
                            |> queryView
                            |> Query.find [ id "pin-icon" ]
                            |> Query.has [ style "background-color" darkGreyHex ]
                , test "mousing off pin icon triggers Hover Nothing msg" <|
                    \_ ->
                        init
                            |> givenResourcePinnedDynamically
                            |> update
                                (Message.Message.Hover <|
                                    Just Message.Message.PinIcon
                                )
                            |> Tuple.first
                            |> queryView
                            |> Query.find [ id "pin-icon" ]
                            |> Event.simulate Event.mouseLeave
                            |> Event.expect
                                (Msgs.Update <| Message.Message.Hover <| Nothing)
                , test "second TogglePinIconHover msg causes pin icon to have transparent background color" <|
                    \_ ->
                        init
                            |> givenResourcePinnedDynamically
                            |> update
                                (Message.Message.Hover <|
                                    Just Message.Message.PinIcon
                                )
                            |> Tuple.first
                            |> update (Message.Message.Hover Nothing)
                            |> Tuple.first
                            |> queryView
                            |> Query.find [ id "pin-icon" ]
                            |> Query.has [ style "background-color" "transparent" ]
                , test "pin bar is not visible when upon successful VersionUnpinned msg" <|
                    \_ ->
                        init
                            |> givenResourcePinnedDynamically
                            |> givenVersionsWithoutPagination
                            |> clickToUnpin
                            |> Application.handleCallback (Callback.VersionUnpinned (Ok ()))
                            |> Tuple.first
                            |> queryView
                            |> Query.findAll [ id "pin-bar" ]
                            |> Query.count (Expect.equal 0)
                , test "pin bar shows unpinned state upon receiving failing (VersionUnpinned) msg" <|
                    \_ ->
                        init
                            |> givenResourcePinnedDynamically
                            |> givenVersionsWithoutPagination
                            |> clickToUnpin
                            |> Application.handleCallback (Callback.VersionUnpinned badResponse)
                            |> Tuple.first
                            |> queryView
                            |> pinBarHasPinnedState version
                , test "pin icon on pin bar is white" <|
                    \_ ->
                        init
                            |> givenResourcePinnedDynamically
                            |> queryView
                            |> Query.find [ id "pin-icon" ]
                            |> Query.has
                                [ style "background-image" <|
                                    Assets.backgroundImage <|
                                        Just Assets.PinIconWhite
                                ]
                ]
            , describe "versions list"
                [ test "version pin states reflect resource pin state" <|
                    \_ ->
                        Resource.init
                            { resourceId =
                                { teamName = teamName
                                , pipelineName = pipelineName
                                , resourceName = resourceName
                                }
                            , paging = Nothing
                            }
                            |> Resource.handleCallback
                                (Callback.ResourceFetched <|
                                    Ok
                                        { teamName = teamName
                                        , pipelineName = pipelineName
                                        , name = resourceName
                                        , failingToCheck = False
                                        , checkError = ""
                                        , checkSetupError = ""
                                        , lastChecked = Nothing
                                        , pinnedVersion = Just (Dict.fromList [ ( "version", version ) ])
                                        , pinnedInConfig = False
                                        , pinComment = Nothing
                                        , icon = Nothing
                                        }
                                )
                                session
                            |> Resource.handleCallback
                                (Callback.VersionedResourcesFetched <|
                                    Ok
                                        ( Nothing
                                        , { content =
                                                [ { id = versionID.versionID
                                                  , version = Dict.fromList [ ( "version", version ) ]
                                                  , metadata = []
                                                  , enabled = True
                                                  }
                                                , { id = otherVersionID.versionID
                                                  , version = Dict.fromList [ ( "version", otherVersion ) ]
                                                  , metadata = []
                                                  , enabled = True
                                                  }
                                                , { id = disabledVersionID.versionID
                                                  , version = Dict.fromList [ ( "version", disabledVersion ) ]
                                                  , metadata = []
                                                  , enabled = False
                                                  }
                                                ]
                                          , pagination =
                                                { previousPage = Nothing
                                                , nextPage = Nothing
                                                }
                                          }
                                        )
                                )
                                session
                            |> Tuple.first
                            |> Resource.versions
                            |> List.map .pinState
                            |> Expect.equal
                                [ PinnedDynamically
                                , NotThePinnedVersion
                                , NotThePinnedVersion
                                ]
                , test "switching pins puts both versions in transition states" <|
                    \_ ->
                        Resource.init
                            { resourceId =
                                { teamName = teamName
                                , pipelineName = pipelineName
                                , resourceName = resourceName
                                }
                            , paging = Nothing
                            }
                            |> Resource.handleCallback
                                (Callback.ResourceFetched <|
                                    Ok
                                        { teamName = teamName
                                        , pipelineName = pipelineName
                                        , name = resourceName
                                        , failingToCheck = False
                                        , checkError = ""
                                        , checkSetupError = ""
                                        , lastChecked = Nothing
                                        , pinnedVersion = Just (Dict.fromList [ ( "version", version ) ])
                                        , pinnedInConfig = False
                                        , pinComment = Nothing
                                        , icon = Nothing
                                        }
                                )
                                session
                            |> Resource.handleCallback
                                (Callback.VersionedResourcesFetched <|
                                    Ok
                                        ( Nothing
                                        , { content =
                                                [ { id = versionID.versionID
                                                  , version = Dict.fromList [ ( "version", version ) ]
                                                  , metadata = []
                                                  , enabled = True
                                                  }
                                                , { id = otherVersionID.versionID
                                                  , version = Dict.fromList [ ( "version", otherVersion ) ]
                                                  , metadata = []
                                                  , enabled = True
                                                  }
                                                , { id = disabledVersionID.versionID
                                                  , version = Dict.fromList [ ( "version", disabledVersion ) ]
                                                  , metadata = []
                                                  , enabled = False
                                                  }
                                                ]
                                          , pagination =
                                                { previousPage = Nothing
                                                , nextPage = Nothing
                                                }
                                          }
                                        )
                                )
                                session
                            |> Resource.update (Click <| PinButton otherVersionID)
                            |> Tuple.first
                            |> Resource.versions
                            |> List.map .pinState
                            |> Expect.equal
                                [ InTransition
                                , InTransition
                                , Disabled
                                ]
                , test "successful PinResource call when switching shows new version pinned" <|
                    \_ ->
                        Resource.init
                            { resourceId =
                                { teamName = teamName
                                , pipelineName = pipelineName
                                , resourceName = resourceName
                                }
                            , paging = Nothing
                            }
                            |> Resource.handleDelivery (ClockTicked OneSecond (Time.millisToPosix 1000))
                            |> Resource.handleCallback
                                (Callback.ResourceFetched <|
                                    Ok
                                        { teamName = teamName
                                        , pipelineName = pipelineName
                                        , name = resourceName
                                        , failingToCheck = False
                                        , checkError = ""
                                        , checkSetupError = ""
                                        , lastChecked = Nothing
                                        , pinnedVersion = Just (Dict.fromList [ ( "version", version ) ])
                                        , pinnedInConfig = False
                                        , pinComment = Nothing
                                        , icon = Nothing
                                        }
                                )
                                session
                            |> Resource.handleCallback
                                (Callback.VersionedResourcesFetched <|
                                    Ok
                                        ( Nothing
                                        , { content =
                                                [ { id = versionID.versionID
                                                  , version = Dict.fromList [ ( "version", version ) ]
                                                  , metadata = []
                                                  , enabled = True
                                                  }
                                                , { id = otherVersionID.versionID
                                                  , version = Dict.fromList [ ( "version", otherVersion ) ]
                                                  , metadata = []
                                                  , enabled = True
                                                  }
                                                , { id = disabledVersionID.versionID
                                                  , version = Dict.fromList [ ( "version", disabledVersion ) ]
                                                  , metadata = []
                                                  , enabled = False
                                                  }
                                                ]
                                          , pagination =
                                                { previousPage = Nothing
                                                , nextPage = Nothing
                                                }
                                          }
                                        )
                                )
                                session
                            |> Resource.update (Click <| PinButton otherVersionID)
                            |> Resource.handleCallback
                                (Callback.VersionPinned <| Ok ())
                                session
                            |> Tuple.first
                            |> Resource.versions
                            |> List.map .pinState
                            |> Expect.equal
                                [ NotThePinnedVersion
                                , PinnedDynamically
                                , NotThePinnedVersion
                                ]
                , test "auto-refresh respects pin switching" <|
                    \_ ->
                        Resource.init
                            { resourceId =
                                { teamName = teamName
                                , pipelineName = pipelineName
                                , resourceName = resourceName
                                }
                            , paging = Nothing
                            }
                            |> Resource.handleDelivery (ClockTicked OneSecond (Time.millisToPosix 1000))
                            |> Resource.handleCallback
                                (Callback.ResourceFetched <|
                                    Ok
                                        { teamName = teamName
                                        , pipelineName = pipelineName
                                        , name = resourceName
                                        , failingToCheck = False
                                        , checkError = ""
                                        , checkSetupError = ""
                                        , lastChecked = Nothing
                                        , pinnedVersion = Just (Dict.fromList [ ( "version", version ) ])
                                        , pinnedInConfig = False
                                        , pinComment = Nothing
                                        , icon = Nothing
                                        }
                                )
                                session
                            |> Resource.handleCallback
                                (Callback.VersionedResourcesFetched <|
                                    Ok
                                        ( Nothing
                                        , { content =
                                                [ { id = versionID.versionID
                                                  , version = Dict.fromList [ ( "version", version ) ]
                                                  , metadata = []
                                                  , enabled = True
                                                  }
                                                , { id = otherVersionID.versionID
                                                  , version = Dict.fromList [ ( "version", otherVersion ) ]
                                                  , metadata = []
                                                  , enabled = True
                                                  }
                                                , { id = disabledVersionID.versionID
                                                  , version = Dict.fromList [ ( "version", disabledVersion ) ]
                                                  , metadata = []
                                                  , enabled = False
                                                  }
                                                ]
                                          , pagination =
                                                { previousPage = Nothing
                                                , nextPage = Nothing
                                                }
                                          }
                                        )
                                )
                                session
                            |> Resource.update (Click <| PinButton otherVersionID)
                            |> Resource.handleCallback
                                (Callback.ResourceFetched <|
                                    Ok
                                        { teamName = teamName
                                        , pipelineName = pipelineName
                                        , name = resourceName
                                        , failingToCheck = False
                                        , checkError = ""
                                        , checkSetupError = ""
                                        , lastChecked = Nothing
                                        , pinnedVersion = Just (Dict.fromList [ ( "version", version ) ])
                                        , pinnedInConfig = False
                                        , pinComment = Nothing
                                        , icon = Nothing
                                        }
                                )
                                session
                            |> Tuple.first
                            |> Resource.versions
                            |> List.map .pinState
                            |> Expect.equal
                                [ InTransition
                                , InTransition
                                , Disabled
                                ]
                , test "checkbox on pinned version has a purple outline" <|
                    \_ ->
                        init
                            |> givenResourcePinnedDynamically
                            |> givenVersionsWithoutPagination
                            |> queryView
                            |> Query.find (versionSelector version)
                            |> Query.find checkboxSelector
                            |> Query.has purpleOutlineSelector
                , test "pin button on pinned version has a pointer cursor" <|
                    \_ ->
                        init
                            |> givenResourcePinnedDynamically
                            |> givenVersionsWithoutPagination
                            |> queryView
                            |> Query.find (versionSelector version)
                            |> Query.find pinButtonSelector
                            |> Query.has pointerCursor
                , test "pin button on an unpinned version has a pointer cursor" <|
                    \_ ->
                        init
                            |> givenResourcePinnedDynamically
                            |> givenVersionsWithoutPagination
                            |> queryView
                            |> Query.find (versionSelector otherVersion)
                            |> Query.find pinButtonSelector
                            |> Query.has pointerCursor
                , test "pin button on pinned version has click handler" <|
                    \_ ->
                        init
                            |> givenResourcePinnedDynamically
                            |> givenVersionsWithoutPagination
                            |> queryView
                            |> Query.find (versionSelector version)
                            |> Query.find pinButtonSelector
                            |> Event.simulate Event.click
                            |> Event.expect
                                (Msgs.Update <|
                                    Message.Message.Click <|
                                        Message.Message.PinButton versionID
                                )
                , test "pin button on pinned version shows transition state when (UnpinVersion) is received" <|
                    \_ ->
                        init
                            |> givenResourcePinnedDynamically
                            |> givenVersionsWithoutPagination
                            |> clickToUnpin
                            |> queryView
                            |> Query.find (versionSelector version)
                            |> Query.find pinButtonSelector
                            |> pinButtonHasTransitionState
                , test "pin button on 'v1' still shows transition state on autorefresh before VersionUnpinned is recieved" <|
                    \_ ->
                        init
                            |> givenResourcePinnedDynamically
                            |> givenVersionsWithoutPagination
                            |> clickToUnpin
                            |> givenResourcePinnedDynamically
                            |> queryView
                            |> Query.find (versionSelector version)
                            |> Query.find pinButtonSelector
                            |> pinButtonHasTransitionState
                , test "version header on pinned version has a purple outline" <|
                    \_ ->
                        init
                            |> givenResourcePinnedDynamically
                            |> givenVersionsWithoutPagination
                            |> queryView
                            |> Query.find (versionSelector version)
                            |> findLast [ tag "div", containing [ text version ] ]
                            |> Query.has purpleOutlineSelector
                , test "pin button on pinned version has a white icon" <|
                    \_ ->
                        init
                            |> givenResourcePinnedDynamically
                            |> givenVersionsWithoutPagination
                            |> queryView
                            |> Query.find (versionSelector version)
                            |> Query.find pinButtonSelector
                            |> Query.has
                                [ style "background-image" <|
                                    Assets.backgroundImage <|
                                        Just Assets.PinIconWhite
                                ]
                , test "does not show tooltip on the pin button on ToggleVersionTooltip" <|
                    \_ ->
                        init
                            |> givenResourcePinnedDynamically
                            |> givenVersionsWithoutPagination
                            |> hoverOverPinButton
                            |> queryView
                            |> Query.find (versionSelector version)
                            |> Query.hasNot versionTooltipSelector
                , test "unpinned versions are lower opacity" <|
                    \_ ->
                        init
                            |> givenResourcePinnedDynamically
                            |> givenVersionsWithoutPagination
                            |> queryView
                            |> Query.find (versionSelector otherVersion)
                            |> Query.has [ style "opacity" "0.5" ]
                , test "all pin buttons have dark background" <|
                    \_ ->
                        init
                            |> givenResourceIsNotPinned
                            |> givenVersionsWithoutPagination
                            |> queryView
                            |> Query.find [ class "resource-versions" ]
                            |> Query.findAll anyVersionSelector
                            |> Query.each
                                (Query.find pinButtonSelector
                                    >> Query.has [ style "background-color" "#1e1d1d" ]
                                )
                ]
            , test "resource refreshes on successful VersionUnpinned msg" <|
                \_ ->
                    init
                        |> givenResourcePinnedDynamically
                        |> givenVersionsWithoutPagination
                        |> clickToUnpin
                        |> Application.handleCallback (Callback.VersionUnpinned (Ok ()))
                        |> Tuple.second
                        |> Expect.equal
                            [ Effects.FetchResource
                                { resourceName = resourceName
                                , pipelineName = pipelineName
                                , teamName = teamName
                                }
                            ]
            , describe "pin comment bar" <|
                let
                    pinCommentBar =
                        init
                            |> givenResourcePinnedWithComment
                            |> commentBar
                in
                [ test "has a grey background" <|
                    \_ ->
                        pinCommentBar
                            |> Query.has
                                [ style "background-color" "#2e2c2c" ]
                , test "has a minimal height of 25 px" <|
                    \_ ->
                        pinCommentBar
                            |> Query.has
                                [ style "min-height" "25px" ]
                , test "takes 50% width of pin tools" <|
                    \_ ->
                        pinCommentBar
                            |> Query.has
                                [ style "flex" "1" ]
                , describe "has an icon container" <|
                    let
                        iconContainer : Application.Model -> Query.Single Msgs.TopLevelMessage
                        iconContainer =
                            commentBar >> Query.children [] >> Query.first
                    in
                    [ test "lays out children horizontally" <|
                        \_ ->
                            init
                                |> givenResourcePinnedWithComment
                                |> iconContainer
                                |> Query.has [ style "display" "flex", style "flex-grow" "1" ]
                    , test "icons align on top of the icon container" <|
                        \_ ->
                            init
                                |> givenResourcePinnedWithComment
                                |> iconContainer
                                |> Query.has [ style "align-items" "flex-start" ]
                    , test "icon div has message icon" <|
                        let
                            iconDiv : Application.Model -> Query.Single Msgs.TopLevelMessage
                            iconDiv =
                                iconContainer >> Query.children [] >> Query.first

                            messageIcon =
                                "baseline-message.svg"
                        in
                        \_ ->
                            init
                                |> givenResourcePinnedWithComment
                                |> iconDiv
                                |> Query.has
                                    [ style "background-image" <|
                                        "url(/public/images/"
                                            ++ messageIcon
                                            ++ ")"
                                    , style "background-size" "contain"
                                    , style "background-position" "50% 50%"
                                    , style "background-repeat" "no-repeat"
                                    , style "width" "25px"
                                    , style "height" "25px"
                                    , style "margin" "10px"
                                    ]
                    , describe "comment pre" <|
                        let
                            commentPre : Query.Single Msgs.TopLevelMessage
                            commentPre =
                                init
                                    |> givenResourcePinnedWithComment
                                    |> iconContainer
                                    |> Query.children []
                                    |> Query.index 1
                        in
                        [ test "displays inline and grows to fill available space" <|
                            \_ ->
                                commentPre |> Query.has [ style "flex-grow" "1", style "margin" "0" ]
                        , test "pre contains the comment" <|
                            \_ ->
                                commentPre |> Query.has [ text "some pin comment" ]
                        , test "has no default outline" <|
                            \_ ->
                                commentPre |> Query.has [ style "outline" "0" ]
                        , test "has vertical padding" <|
                            \_ ->
                                commentPre |> Query.has [ style "padding" "10px 0" ]
                        ]
                    , describe "edit button" <|
                        let
                            editButton =
                                init
                                    |> givenUserIsAuthorized
                                    |> givenResourcePinnedWithComment
                                    |> iconContainer
                                    |> Query.find [ id "edit-button" ]
                        in
                        [ test "only shows up when user is authorized" <|
                            \_ ->
                                init
                                    |> givenUserIsAuthorized
                                    |> givenResourcePinnedWithComment
                                    |> commentBar
                                    |> Query.has [ id "edit-button" ]
                        , test "edit button is on the far right" <|
                            \_ ->
                                init
                                    |> givenUserIsAuthorized
                                    |> givenResourcePinnedWithComment
                                    |> iconContainer
                                    |> Query.children []
                                    |> Query.index -1
                                    |> Query.has [ id "edit-button" ]
                        , test "has the pencil icon" <|
                            \_ ->
                                editButton
                                    |> Query.has (iconSelector { size = "25px", image = "pencil-24px.svg" })
                        , test "has padding of 5 px" <|
                            \_ ->
                                editButton
                                    |> Query.has [ style "padding" "5px" ]
                        , test "has a pointer cursor" <|
                            \_ ->
                                editButton
                                    |> Query.has [ style "cursor" "pointer" ]
                        , defineHoverBehaviour
                            { name = "edit button"
                            , setup = init |> givenUserIsAuthorized |> givenResourcePinnedWithComment
                            , query = iconContainer >> Query.find [ id "edit-button" ]
                            , unhoveredSelector =
                                { description = "transparent background"
                                , selector = []
                                }
                            , hoverable = Message.Message.EditButton
                            , hoveredSelector =
                                { description = "dark background"
                                , selector =
                                    [ style "background-color" almostBlack ]
                                }
                            }
                        , test "has a click handler" <|
                            \_ ->
                                editButton
                                    |> Event.simulate Event.click
                                    |> Event.expect
                                        (Msgs.Update <|
                                            Message.Message.Click <|
                                                Message.Message.EditButton
                                        )
                        , test "after clicking on edit button, the background turns purple" <|
                            \_ ->
                                init
                                    |> givenResourcePinnedWithComment
                                    |> update
                                        (Message.Message.Click <|
                                            Message.Message.EditButton
                                        )
                                    |> Tuple.first
                                    |> iconContainer
                                    |> Query.has [ style "background-color" purpleHex ]
                        , test "after clicking on edit button, edit button disappears" <|
                            \_ ->
                                init
                                    |> givenUserIsAuthorized
                                    |> givenResourcePinnedWithComment
                                    |> update
                                        (Message.Message.Click <|
                                            Message.Message.EditButton
                                        )
                                    |> Tuple.first
                                    |> iconContainer
                                    |> Query.hasNot [ id "edit-button" ]
                        , test "after clicking on edit button, there's a save button" <|
                            \_ ->
                                init
                                    |> givenUserIsAuthorized
                                    |> givenResourcePinnedWithComment
                                    |> update
                                        (Message.Message.Click <|
                                            Message.Message.EditButton
                                        )
                                    |> Tuple.first
                                    |> iconContainer
                                    |> Query.has [ tag "button" ]
                        ]
                    , describe "textarea" <|
                        let
                            textarea =
                                init
                                    |> givenUserIsAuthorized
                                    |> givenResourcePinnedWithComment
                                    |> commentBar
                                    |> Query.find [ tag "textarea" ]

                            whenUserEditsComment =
                                update (Message.Message.EditComment "foo")

                            givenUserEditedComment =
                                whenUserEditsComment
                                    >> Tuple.first
                        in
                        [ test "only shows up when user is authorized and editing" <|
                            \_ ->
                                init
                                    |> givenUserIsAuthorized
                                    |> givenResourcePinnedWithComment
                                    |> commentBar
                                    |> Query.has [ tag "textarea" ]
                        , test "has comment as value" <|
                            \_ ->
                                textarea
                                    |> Query.has
                                        [ attribute <|
                                            Attr.value "some pin comment"
                                        ]
                        , test "has the id resource_comment" <|
                            \_ ->
                                textarea |> Query.has [ id "resource_comment" ]
                        , test "has a transparent background" <|
                            \_ ->
                                textarea |> Query.has [ style "background-color" "transparent" ]
                        , test "has no border or outline" <|
                            \_ ->
                                textarea |> Query.has [ style "outline" "none", style "border" "none" ]
                        , test "has the text color" <|
                            \_ ->
                                textarea |> Query.has [ style "color" "#e6e7e8" ]
                        , test "has no resize handler" <|
                            \_ ->
                                textarea |> Query.has [ style "resize" "none" ]
                        , test "has border-box" <|
                            \_ ->
                                textarea
                                    |> Query.has [ style "box-sizing" "border-box" ]
                        , test "matches app font" <|
                            \_ ->
                                textarea
                                    |> Query.has
                                        [ style "font-size" "12px"
                                        , style "font-family" "Inconsolata, monospace"
                                        , style "font-weight" "700"
                                        ]
                        , test "has a max height of 150px" <|
                            \_ ->
                                textarea
                                    |> Query.has [ style "max-height" "150px" ]
                        , test "has flex-grow 1" <|
                            \_ ->
                                textarea
                                    |> Query.has [ style "flex-grow" "1" ]
                        , test "has a top and bottom margin of 10px" <|
                            \_ ->
                                textarea
                                    |> Query.has [ style "margin" "10px 0" ]
                        , test "is readonly when not editing" <|
                            \_ ->
                                textarea
                                    |> Query.has [ attribute <| Attr.readonly True ]
                        , describe "sync textarea height" <|
                            [ test "sync when editing" <|
                                \_ ->
                                    init
                                        |> givenUserIsAuthorized
                                        |> givenResourcePinnedWithComment
                                        |> whenUserEditsComment
                                        |> Tuple.second
                                        |> Common.contains (Effects.SyncTextareaHeight ResourceCommentTextarea)
                            , test "sync when resource is first loaded" <|
                                \_ ->
                                    init
                                        |> givenUserIsAuthorized
                                        |> whenResourceLoadsWithPinnedComment
                                        |> Tuple.second
                                        |> Common.contains (Effects.SyncTextareaHeight ResourceCommentTextarea)
                            ]
                        , describe "when editing the textarea" <|
                            [ test "is not readonly" <|
                                \_ ->
                                    init
                                        |> givenUserIsAuthorized
                                        |> givenResourcePinnedWithComment
                                        |> givenUserEditedComment
                                        |> Application.update (Msgs.Update <| Message.Message.Click Message.Message.EditButton)
                                        |> Tuple.first
                                        |> queryView
                                        |> Query.find [ tag "textarea" ]
                                        |> Query.has [ attribute <| Attr.readonly False ]
                            , test "input in textarea produces EditComment msg" <|
                                \_ ->
                                    textarea
                                        |> Event.simulate (Event.input "foo")
                                        |> Event.expect
                                            (Msgs.Update <|
                                                Message.Message.EditComment "foo"
                                            )
                            , test "EditComment updates textarea value" <|
                                \_ ->
                                    init
                                        |> givenUserIsAuthorized
                                        |> givenResourcePinnedWithComment
                                        |> givenUserEditedComment
                                        |> queryView
                                        |> Query.find [ tag "textarea" ]
                                        |> Query.has [ attribute <| Attr.value "foo" ]
                            , test "autorefresh doesn't change textarea" <|
                                \_ ->
                                    init
                                        |> givenUserIsAuthorized
                                        |> givenResourcePinnedWithComment
                                        |> givenUserEditedComment
                                        |> givenResourcePinnedWithComment
                                        |> queryView
                                        |> Query.find [ tag "textarea" ]
                                        |> Query.has
                                            [ attribute <| Attr.value "foo" ]
                            , test "focusing textarea triggers FocusTextArea msg" <|
                                \_ ->
                                    textarea
                                        |> Event.simulate Event.focus
                                        |> Event.expect
                                            (Msgs.Update
                                                Message.Message.FocusTextArea
                                            )
                            , test "keydown subscription active when textarea is focused" <|
                                \_ ->
                                    init
                                        |> givenUserIsAuthorized
                                        |> givenResourcePinnedWithComment
                                        |> givenTextareaFocused
                                        |> Application.subscriptions
                                        |> Common.contains Subscription.OnKeyDown
                            , test "keyup subscription active when textarea is focused" <|
                                \_ ->
                                    init
                                        |> givenUserIsAuthorized
                                        |> givenResourcePinnedWithComment
                                        |> givenTextareaFocused
                                        |> Application.subscriptions
                                        |> Common.contains Subscription.OnKeyUp
                            , test "Ctrl-Enter sends SaveComment msg" <|
                                \_ ->
                                    init
                                        |> givenUserIsAuthorized
                                        |> givenResourcePinnedWithComment
                                        |> givenUserEditedComment
                                        |> givenTextareaFocused
                                        |> pressControlEnter
                                        |> Tuple.second
                                        |> Expect.equal
                                            [ Effects.SetPinComment
                                                { teamName = teamName
                                                , pipelineName = pipelineName
                                                , resourceName = resourceName
                                                }
                                                "foo"
                                            ]
                            , test "Command + Enter sends SaveComment msg" <|
                                \_ ->
                                    init
                                        |> givenUserIsAuthorized
                                        |> givenResourcePinnedWithComment
                                        |> givenUserEditedComment
                                        |> givenTextareaFocused
                                        |> pressMetaEnter
                                        |> Tuple.second
                                        |> Expect.equal
                                            [ Effects.SetPinComment
                                                { teamName = teamName
                                                , pipelineName = pipelineName
                                                , resourceName = resourceName
                                                }
                                                "foo"
                                            ]
                            , test "blurring input triggers BlurTextArea msg" <|
                                \_ ->
                                    textarea
                                        |> Event.simulate Event.blur
                                        |> Event.expect
                                            (Msgs.Update
                                                Message.Message.BlurTextArea
                                            )
                            , test "Ctrl-Enter after blurring input does nothing" <|
                                \_ ->
                                    init
                                        |> givenUserIsAuthorized
                                        |> givenResourcePinnedWithComment
                                        |> givenUserEditedComment
                                        |> givenTextareaFocused
                                        |> givenTextareaBlurred
                                        |> pressControlEnter
                                        |> Tuple.second
                                        |> Expect.equal []
                            , test "releasing Ctrl key and pressing enter does nothing" <|
                                \_ ->
                                    init
                                        |> givenUserIsAuthorized
                                        |> givenResourcePinnedWithComment
                                        |> givenUserEditedComment
                                        |> givenTextareaFocused
                                        |> pressEnterKey
                                        |> Tuple.second
                                        |> Expect.equal []
                            ]
                        ]
                    ]
                ]
            ]
        , describe "given resource is not pinned"
            [ test "pin tool is not visible" <|
                \_ ->
                    init
                        |> givenResourceIsNotPinned
                        |> queryView
                        |> Query.hasNot [ id "pin-tools" ]
            , test "pin bar is not visible" <|
                \_ ->
                    init
                        |> givenResourceIsNotPinned
                        |> queryView
                        |> Query.hasNot [ id "pin-bar" ]
            , test "pin comment bar is not visible" <|
                \_ ->
                    init
                        |> givenResourceIsNotPinned
                        |> queryView
                        |> Query.hasNot [ id "comment-bar" ]
            , test "then nothing has purple border" <|
                \_ ->
                    init
                        |> givenResourceIsNotPinned
                        |> queryView
                        |> Query.hasNot purpleOutlineSelector
            , describe "version headers" <|
                let
                    allVersions : () -> Query.Multiple Msgs.TopLevelMessage
                    allVersions _ =
                        init
                            |> givenResourceIsNotPinned
                            |> givenVersionsWithoutPagination
                            |> queryView
                            |> Query.find [ class "resource-versions" ]
                            |> Query.findAll anyVersionSelector
                in
                [ test "contain elements that are black with a black border" <|
                    allVersions
                        >> Query.each
                            (Query.children []
                                >> Query.first
                                >> Query.children []
                                >> Query.each
                                    (Query.has
                                        [ style "border" <|
                                            "1px solid "
                                                ++ almostBlack
                                        , style "background-color"
                                            almostBlack
                                        ]
                                    )
                            )
                , test "checkboxes are 25px x 25px with icon-type backgrounds" <|
                    allVersions
                        >> Query.each
                            (Query.children []
                                >> Query.first
                                >> Query.children []
                                >> Query.first
                                >> Query.has
                                    [ style "margin-right" "5px"
                                    , style "width" "25px"
                                    , style "height" "25px"
                                    , style "background-repeat" "no-repeat"
                                    , style "background-position" "50% 50%"
                                    ]
                            )
                , test "pin buttons are 25px x 25px with icon-type backgrounds" <|
                    allVersions
                        >> Query.each
                            (Query.children []
                                >> Query.first
                                >> Query.children []
                                >> Query.index 1
                                >> Query.has
                                    [ style "margin-right" "5px"
                                    , style "width" "25px"
                                    , style "height" "25px"
                                    , style "background-repeat" "no-repeat"
                                    , style "background-position" "50% 50%"
                                    ]
                            )
                , test "pin buttons are positioned to anchor their tooltips" <|
                    allVersions
                        >> Query.each
                            (Query.children []
                                >> Query.first
                                >> Query.children []
                                >> Query.index 1
                                >> Query.has
                                    [ style "position" "relative" ]
                            )
                , test "version headers lay out horizontally, centering" <|
                    allVersions
                        >> Query.each
                            (Query.children []
                                >> Query.first
                                >> Query.children []
                                >> Query.index 2
                                >> Query.has
                                    [ style "display" "flex"
                                    , style "align-items" "center"
                                    ]
                            )
                , test "version headers fill horizontal space" <|
                    allVersions
                        >> Query.each
                            (Query.children []
                                >> Query.first
                                >> Query.children []
                                >> Query.index 2
                                >> Query.has
                                    [ style "flex-grow" "1" ]
                            )
                , test "version headers have pointer cursor" <|
                    allVersions
                        >> Query.each
                            (Query.children []
                                >> Query.first
                                >> Query.children []
                                >> Query.index 2
                                >> Query.has
                                    [ style "cursor" "pointer" ]
                            )
                , test "version headers have contents offset from the left" <|
                    allVersions
                        >> Query.each
                            (Query.children []
                                >> Query.first
                                >> Query.children []
                                >> Query.index 2
                                >> Query.has
                                    [ style "padding-left" "10px" ]
                            )
                ]
            , test "clicking pin icon on pin bar does nothing" <|
                \_ ->
                    init
                        |> givenResourceIsNotPinned
                        |> queryView
                        |> Query.find [ id "pin-icon" ]
                        |> Event.simulate Event.click
                        |> Event.toResult
                        |> Expect.err
            , test "mousing over pin icon does nothing" <|
                \_ ->
                    init
                        |> givenResourceIsNotPinned
                        |> queryView
                        |> Query.find [ id "pin-icon" ]
                        |> Event.simulate Event.mouseEnter
                        |> Event.toResult
                        |> Expect.err
            , test "does not show tooltip on the pin icon on ToggleVersionTooltip" <|
                \_ ->
                    init
                        |> givenResourceIsNotPinned
                        |> givenVersionsWithoutPagination
                        |> hoverOverPinButton
                        |> queryView
                        |> Query.find (versionSelector version)
                        |> Query.hasNot versionTooltipSelector
            , test "all pin buttons have pointer cursor" <|
                \_ ->
                    init
                        |> givenResourceIsNotPinned
                        |> givenVersionsWithoutPagination
                        |> queryView
                        |> Query.find [ class "resource-versions" ]
                        |> Query.findAll anyVersionSelector
                        |> Query.each
                            (Query.find pinButtonSelector
                                >> Query.has pointerCursor
                            )
            , test "all pin buttons have dark background" <|
                \_ ->
                    init
                        |> givenResourceIsNotPinned
                        |> givenVersionsWithoutPagination
                        |> queryView
                        |> Query.find [ class "resource-versions" ]
                        |> Query.findAll anyVersionSelector
                        |> Query.each
                            (Query.find pinButtonSelector
                                >> Query.has [ style "background-color" "#1e1d1d" ]
                            )
            , describe "clicking pin buttons" <|
                let
                    setup _ =
                        init
                            |> Application.handleCallback
                                (Callback.UserFetched <|
                                    Ok
                                        { id = "some-user"
                                        , userName = "some-user"
                                        , name = "some-user"
                                        , email = "some-user"
                                        , isAdmin = False
                                        , teams =
                                            Dict.fromList
                                                [ ( "some-team"
                                                  , [ "member" ]
                                                  )
                                                ]
                                        }
                                )
                            |> Tuple.first
                            |> Application.update
                                (Msgs.DeliveryReceived <|
                                    ClockTicked
                                        OneSecond
                                        (Time.millisToPosix 0)
                                )
                            |> Tuple.first
                            |> givenResourceIsNotPinned
                            |> givenVersionsWithoutPagination
                in
                [ test "pin button on 'v1' has click handler" <|
                    setup
                        >> queryView
                        >> Query.find (versionSelector version)
                        >> Query.find pinButtonSelector
                        >> Event.simulate Event.click
                        >> Event.expect
                            (Msgs.Update <|
                                Message.Message.Click <|
                                    Message.Message.PinButton versionID
                            )
                , describe "after clicking 'v1' pin button" <|
                    let
                        afterClick =
                            setup >> clickToPin versionID
                    in
                    [ test "clicked button shows transition state" <|
                        afterClick
                            >> queryView
                            >> Query.find (versionSelector version)
                            >> Query.find pinButtonSelector
                            >> pinButtonHasTransitionState
                    , test "other pin buttons disabled" <|
                        afterClick
                            >> queryView
                            >> Query.find (versionSelector otherVersion)
                            >> Query.find pinButtonSelector
                            >> Event.simulate Event.click
                            >> Event.toResult
                            >> Expect.err
                    , test "pin bar shows unpinned state" <|
                        afterClick
                            >> queryView
                            >> pinToolsHasTransitionState
                    , test "autorefresh respects transition state" <|
                        afterClick
                            >> givenResourceIsNotPinned
                            >> queryView
                            >> Query.find (versionSelector version)
                            >> Query.find pinButtonSelector
                            >> pinButtonHasTransitionState
                    , describe "when pinning succeeds" <|
                        let
                            onSuccess =
                                afterClick
                                    >> Application.handleCallback
                                        (Callback.VersionPinned <| Ok ())
                        in
                        [ test "pin bar reflects 'v1'" <|
                            onSuccess
                                >> Tuple.first
                                >> queryView
                                >> pinBarHasPinnedState version
                        , test "automatically tries to set comment" <|
                            onSuccess
                                >> Tuple.second
                                >> Expect.equal
                                    [ Effects.SetPinComment
                                        { teamName = teamName
                                        , pipelineName = pipelineName
                                        , resourceName = resourceName
                                        }
                                        "pinned by some-user at Jan 1 1970 12:00:00 AM"
                                    ]
                        ]
                    , test "clicked button shows unpinned state when pinning fails" <|
                        afterClick
                            >> Application.handleCallback
                                (Callback.VersionPinned badResponse)
                            >> Tuple.first
                            >> queryView
                            >> Query.find (versionSelector version)
                            >> Query.find pinButtonSelector
                            >> pinButtonHasUnpinnedState
                    ]
                ]
            ]
        , describe "pin tools" <|
            let
                pinTools =
                    init
                        |> givenResourcePinnedDynamically
                        |> queryView
                        |> Query.find [ id "pin-tools" ]
            in
            [ test "has grey background" <|
                \_ ->
                    pinTools
                        |> Query.has [ style "background-color" "#2e2c2c" ]
            , test "has a minimal height of 28 px" <|
                \_ ->
                    pinTools
                        |> Query.has [ style "min-height" "28px" ]
            , test "not display check status bar when resources being pinned" <|
                \_ ->
                    init
                        |> givenResourcePinnedDynamically
                        |> queryView
                        |> Query.hasNot [ class "resource-check-status" ]
            , test "only appears when the resource is pinned" <|
                \_ ->
                    init
                        |> givenResourceIsNotPinned
                        |> queryView
                        |> Query.hasNot [ id "pin-tools" ]
            , test "has a bottom margin of 24 px" <|
                \_ ->
                    pinTools
                        |> Query.has [ style "margin-bottom" "24px" ]
            , test "shows a pinned version" <|
                \_ ->
                    pinTools
                        |> Query.has [ text version ]
            , test "version text vertically centers" <|
                \_ ->
                    pinTools
                        |> Query.has [ style "display" "flex", style "align-items" "center" ]
            , test "after pinning it has a purple border" <|
                \_ ->
                    pinTools
                        |> Query.has purpleOutlineSelector
            , test "pin tools size includes its border" <|
                \_ ->
                    pinTools
                        |> Query.has [ style "box-sizing" "border-box" ]
            , test "contains pin bar on the left" <|
                \_ ->
                    pinTools
                        |> Query.children []
                        |> Query.index 0
                        |> Query.has [ id "pin-bar" ]
            , test "contains pin comment bar on the right" <|
                \_ ->
                    pinTools
                        |> Query.children []
                        |> Query.index 1
                        |> Query.has [ id "comment-bar" ]
            , test "pin bar and comment bar each takes 50% width" <|
                \_ ->
                    pinTools
                        |> Query.has [ style "display" "flex" ]
            ]
        , describe "check status" <|
            let
                checkBar userState =
                    let
                        callback =
                            case userState of
                                UserStateLoggedIn user ->
                                    UserFetched (Ok user)

                                UserStateLoggedOut ->
                                    LoggedOut (Ok ())

                                UserStateUnknown ->
                                    EmptyCallback
                    in
                    Application.handleCallback callback
                        >> Tuple.first
                        >> queryView
                        >> Query.find [ class "resource-check-status" ]
                        >> Query.children []
                        >> Query.first
            in
            [ test "lays out horizontally" <|
                \_ ->
                    init
                        |> givenResourceIsNotPinned
                        |> checkBar UserStateLoggedOut
                        |> Query.has [ style "display" "flex" ]
            , test "has two children: check button and status bar" <|
                \_ ->
                    init
                        |> givenResourceIsNotPinned
                        |> checkBar UserStateLoggedOut
                        |> Query.children []
                        |> Query.count (Expect.equal 2)
            , describe "status bar"
                [ test "lays out horizontally and spreads its children" <|
                    \_ ->
                        init
                            |> givenResourceIsNotPinned
                            |> checkBar UserStateLoggedOut
                            |> Query.children []
                            |> Query.index 1
                            |> Query.has
                                [ style "display" "flex"
                                , style "justify-content" "space-between"
                                ]
                , test "fills out the check bar and centers children" <|
                    \_ ->
                        init
                            |> givenResourceIsNotPinned
                            |> checkBar UserStateLoggedOut
                            |> Query.children []
                            |> Query.index 1
                            |> Query.has
                                [ style "align-items" "center"
                                , style "height" "28px"
                                , style "flex-grow" "1"
                                , style "padding-left" "5px"
                                ]
                , test "has a dark grey background" <|
                    \_ ->
                        init
                            |> givenResourceIsNotPinned
                            |> checkBar UserStateLoggedOut
                            |> Query.children []
                            |> Query.index 1
                            |> Query.has
                                [ style "background" "#1e1d1d" ]
                ]
            , describe "when unauthenticated"
                [ defineHoverBehaviour
                    { name = "check button"
                    , setup = init |> givenResourceIsNotPinned
                    , query = checkBar UserStateLoggedOut >> Query.children [] >> Query.first
                    , unhoveredSelector =
                        { description = "black button with grey refresh icon"
                        , selector =
                            [ style "height" "28px"
                            , style "width" "28px"
                            , style "background-color" almostBlack
                            , style "margin-right" "5px"
                            , containing <|
                                iconSelector
                                    { size = "20px"
                                    , image = Assets.RefreshIcon
                                    }
                                    ++ [ style "opacity" "0.5"
                                       , style "margin" "4px"
                                       ]
                            ]
                        }
                    , hoverable = Message.Message.CheckButton False
                    , hoveredSelector =
                        { description = "black button with white refresh icon"
                        , selector =
                            [ style "height" "28px"
                            , style "width" "28px"
                            , style "background-color" almostBlack
                            , style "margin-right" "5px"
                            , style "cursor" "pointer"
                            , containing <|
                                iconSelector
                                    { size = "20px"
                                    , image = Assets.RefreshIcon
                                    }
                                    ++ [ style "opacity" "1"
                                       , style "margin" "4px"
                                       , style "background-size" "contain"
                                       ]
                            ]
                        }
                    }
                , test "clicking check button sends Check msg" <|
                    \_ ->
                        init
                            |> givenResourceIsNotPinned
                            |> checkBar UserStateLoggedOut
                            |> Query.children []
                            |> Query.first
                            |> Event.simulate Event.click
                            |> Event.expect
                                (Msgs.Update <|
                                    Message.Message.Click <|
                                        Message.Message.CheckButton False
                                )
                , test "Check msg redirects to login" <|
                    \_ ->
                        init
                            |> givenResourceIsNotPinned
                            |> update
                                (Message.Message.Click <|
                                    Message.Message.CheckButton False
                                )
                            |> Tuple.second
                            |> Expect.equal [ Effects.RedirectToLogin ]
                , test "check bar text does not change" <|
                    \_ ->
                        init
                            |> givenResourceIsNotPinned
                            |> update
                                (Message.Message.Click <|
                                    Message.Message.CheckButton False
                                )
                            |> Tuple.first
                            |> checkBar UserStateLoggedOut
                            |> Query.find [ tag "h3" ]
                            |> Query.has [ text "checking successfully" ]
                ]
            , describe "when authorized" <|
                let
                    sampleUser : Concourse.User
                    sampleUser =
                        { id = "test"
                        , userName = "test"
                        , name = "test"
                        , email = "test"
                        , isAdmin = False
                        , teams = Dict.fromList [ ( teamName, [ "member" ] ) ]
                        }
                in
                [ defineHoverBehaviour
                    { name = "check button when authorized"
                    , setup =
                        init
                            |> givenResourceIsNotPinned
                    , query = checkBar (UserStateLoggedIn sampleUser) >> Query.children [] >> Query.first
                    , unhoveredSelector =
                        { description = "black button with grey refresh icon"
                        , selector =
                            [ style "height" "28px"
                            , style "width" "28px"
                            , style "background-color" almostBlack
                            , style "margin-right" "5px"
                            , containing <|
                                iconSelector
                                    { size = "20px"
                                    , image = Assets.RefreshIcon
                                    }
                                    ++ [ style "opacity" "0.5"
                                       , style "margin" "4px"
                                       ]
                            ]
                        }
                    , hoverable = Message.Message.CheckButton True
                    , hoveredSelector =
                        { description = "black button with white refresh icon"
                        , selector =
                            [ style "height" "28px"
                            , style "width" "28px"
                            , style "background-color" almostBlack
                            , style "margin-right" "5px"
                            , style "cursor" "pointer"
                            , containing <|
                                iconSelector
                                    { size = "20px"
                                    , image = Assets.RefreshIcon
                                    }
                                    ++ [ style "opacity" "1"
                                       , style "margin" "4px"
                                       , style "background-size" "contain"
                                       ]
                            ]
                        }
                    }
                , test "clicking check button sends Click msg" <|
                    \_ ->
                        init
                            |> givenResourceIsNotPinned
                            |> checkBar (UserStateLoggedIn sampleUser)
                            |> Query.children []
                            |> Query.first
                            |> Event.simulate Event.click
                            |> Event.expect
                                (Msgs.Update
                                    (Message.Message.Click <|
                                        Message.Message.CheckButton True
                                    )
                                )
                , test "Click msg has CheckResource side effect" <|
                    \_ ->
                        init
                            |> givenResourceIsNotPinned
                            |> givenUserIsAuthorized
                            |> update
                                (Message.Message.Click <|
                                    Message.Message.CheckButton True
                                )
                            |> Tuple.second
                            |> Expect.equal
                                [ Effects.DoCheck
                                    { resourceName = resourceName
                                    , pipelineName = pipelineName
                                    , teamName = teamName
                                    }
                                ]
                , describe "while check is pending" <|
                    let
                        givenCheckInProgress : Application.Model -> Application.Model
                        givenCheckInProgress =
                            givenResourceIsNotPinned
                                >> givenUserIsAuthorized
                                >> update
                                    (Message.Message.Click <|
                                        Message.Message.CheckButton True
                                    )
                                >> Tuple.first
                    in
                    [ test "check bar text says 'check pending'" <|
                        \_ ->
                            init
                                |> givenCheckInProgress
                                |> checkBar (UserStateLoggedIn sampleUser)
                                |> Query.find [ tag "h3" ]
                                |> Query.has [ text "check pending" ]
                    , test "clicking check button does nothing" <|
                        \_ ->
                            init
                                |> givenCheckInProgress
                                |> checkBar (UserStateLoggedIn sampleUser)
                                |> Query.children []
                                |> Query.first
                                |> Event.simulate Event.click
                                |> Event.toResult
                                |> Expect.err
                    , test "status icon is spinner" <|
                        \_ ->
                            init
                                |> givenCheckInProgress
                                |> checkBar (UserStateLoggedIn sampleUser)
                                |> Query.children []
                                |> Query.index -1
                                |> Query.has
                                    [ style "display" "flex"
                                    , containing
                                        [ style "animation" <|
                                            "container-rotate 1568ms "
                                                ++ "linear infinite"
                                        , style "height" "14px"
                                        , style "width" "14px"
                                        , style "margin" "7px"
                                        ]
                                    ]
                    , defineHoverBehaviour
                        { name = "check button"
                        , setup = init |> givenCheckInProgress
                        , query = checkBar (UserStateLoggedIn sampleUser) >> Query.children [] >> Query.first
                        , unhoveredSelector =
                            { description = "black button with white refresh icon"
                            , selector =
                                [ style "height" "28px"
                                , style "width" "28px"
                                , style "background-color" almostBlack
                                , style "margin-right" "5px"
                                , style "cursor" "default"
                                , containing <|
                                    iconSelector
                                        { size = "20px"
                                        , image = Assets.RefreshIcon
                                        }
                                        ++ [ style "opacity" "1"
                                           , style "margin" "4px"
                                           ]
                                ]
                            }
                        , hoverable = Message.Message.CheckButton True
                        , hoveredSelector =
                            { description = "black button with white refresh icon"
                            , selector =
                                [ style "height" "28px"
                                , style "width" "28px"
                                , style "background-color" almostBlack
                                , style "margin-right" "5px"
                                , style "cursor" "default"
                                , containing <|
                                    iconSelector
                                        { size = "20px"
                                        , image = Assets.RefreshIcon
                                        }
                                        ++ [ style "opacity" "1"
                                           , style "margin" "4px"
                                           ]
                                ]
                            }
                        }
                    ]
                , test "when check resolves successfully, shows checkmark" <|
                    \_ ->
                        init
                            |> givenResourceIsNotPinned
                            |> givenUserIsAuthorized
                            |> update
                                (Message.Message.Click <|
                                    Message.Message.CheckButton True
                                )
                            |> Tuple.first
                            |> Application.handleCallback
                                (Callback.Checked <|
                                    Ok <|
                                        Data.check Concourse.Succeeded
                                )
                            |> Tuple.first
                            |> checkBar (UserStateLoggedIn sampleUser)
                            |> Query.children []
                            |> Query.index -1
                            |> Query.has
                                (iconSelector
                                    { size = "28px"
                                    , image = Assets.SuccessCheckIcon
                                    }
                                    ++ [ style "background-size" "14px 14px" ]
                                )
                , test "when check returns 'started', refreshes on 1s tick" <|
                    \_ ->
                        init
                            |> givenResourceIsNotPinned
                            |> givenUserIsAuthorized
                            |> update
                                (Message.Message.Click <|
                                    Message.Message.CheckButton True
                                )
                            |> Tuple.first
                            |> Application.handleCallback
                                (Callback.Checked <|
                                    Ok <|
                                        Data.check Concourse.Started
                                )
                            |> Tuple.first
                            |> Application.handleDelivery
                                (ClockTicked OneSecond <|
                                    Time.millisToPosix 1000
                                )
                            |> Tuple.second
                            |> Common.contains (Effects.FetchCheck 0)
                , test "when check resolves successfully, resource and versions refresh" <|
                    \_ ->
                        init
                            |> givenResourceIsNotPinned
                            |> givenUserIsAuthorized
                            |> update
                                (Message.Message.Click <|
                                    Message.Message.CheckButton True
                                )
                            |> Tuple.first
                            |> Application.handleCallback
                                (Callback.Checked <|
                                    Ok <|
                                        Data.check Concourse.Succeeded
                                )
                            |> Tuple.second
                            |> Expect.equal
                                [ Effects.FetchResource
                                    { resourceName = resourceName
                                    , pipelineName = pipelineName
                                    , teamName = teamName
                                    }
                                , Effects.FetchVersionedResources
                                    { resourceName = resourceName
                                    , pipelineName = pipelineName
                                    , teamName = teamName
                                    }
                                    Nothing
                                ]
                , test "when check resolves unsuccessfully, status is error" <|
                    \_ ->
                        init
                            |> givenResourceIsNotPinned
                            |> givenUserIsAuthorized
                            |> update
                                (Message.Message.Click <|
                                    Message.Message.CheckButton True
                                )
                            |> Tuple.first
                            |> Application.handleCallback
                                (Callback.Checked <|
                                    Ok <|
                                        Data.check Concourse.Errored
                                )
                            |> Tuple.first
                            |> checkBar (UserStateLoggedIn sampleUser)
                            |> Query.children []
                            |> Query.index -1
                            |> Query.has
                                (iconSelector
                                    { size = "28px"
                                    , image = Assets.ExclamationTriangleIcon
                                    }
                                    ++ [ style "background-size" "14px 14px" ]
                                )
                , test "when check resolves unsuccessfully, resource refreshes" <|
                    \_ ->
                        init
                            |> givenResourceIsNotPinned
                            |> givenUserIsAuthorized
                            |> update
                                (Message.Message.Click <|
                                    Message.Message.CheckButton True
                                )
                            |> Tuple.first
                            |> Application.handleCallback
                                (Callback.Checked <|
                                    Ok <|
                                        Data.check Concourse.Errored
                                )
                            |> Tuple.second
                            |> Expect.equal
                                [ Effects.FetchResource
                                    { resourceName = resourceName
                                    , pipelineName = pipelineName
                                    , teamName = teamName
                                    }
                                ]
                , test "when check returns 401, redirects to login" <|
                    \_ ->
                        init
                            |> givenResourceIsNotPinned
                            |> givenUserIsAuthorized
                            |> update
                                (Message.Message.Click <|
                                    Message.Message.CheckButton True
                                )
                            |> Tuple.first
                            |> Application.handleCallback
                                (Callback.Checked <|
                                    Err <|
                                        Http.BadStatus
                                            { url = ""
                                            , status =
                                                { code = 401
                                                , message = "unauthorized"
                                                }
                                            , headers = Dict.empty
                                            , body = ""
                                            }
                                )
                            |> Tuple.second
                            |> Expect.equal [ Effects.RedirectToLogin ]
                ]
            , describe "when unauthorized" <|
                let
                    sampleUser : Concourse.User
                    sampleUser =
                        { id = "test"
                        , userName = "test"
                        , name = "test"
                        , email = "test"
                        , isAdmin = False
                        , teams = Dict.fromList [ ( teamName, [ "viewer" ] ) ]
                        }
                in
                [ defineHoverBehaviour
                    { name = "check button"
                    , setup =
                        init
                            |> givenResourceIsNotPinned
                    , query = checkBar (UserStateLoggedIn sampleUser) >> Query.children [] >> Query.first
                    , unhoveredSelector =
                        { description = "black button with grey refresh icon"
                        , selector =
                            [ style "height" "28px"
                            , style "width" "28px"
                            , style "background-color" almostBlack
                            , style "margin-right" "5px"
                            , containing <|
                                iconSelector
                                    { size = "20px"
                                    , image = Assets.RefreshIcon
                                    }
                                    ++ [ style "opacity" "0.5"
                                       , style "margin" "4px"
                                       ]
                            ]
                        }
                    , hoverable = Message.Message.CheckButton False
                    , hoveredSelector =
                        { description = "black button with grey refresh icon"
                        , selector =
                            [ style "height" "28px"
                            , style "width" "28px"
                            , style "background-color" almostBlack
                            , style "margin-right" "5px"
                            , containing <|
                                iconSelector
                                    { size = "20px"
                                    , image = Assets.RefreshIcon
                                    }
                                    ++ [ style "opacity" "0.5"
                                       , style "margin" "4px"
                                       ]
                            ]
                        }
                    }
                , test "clicking check button does nothing" <|
                    \_ ->
                        init
                            |> givenResourceIsNotPinned
                            |> checkBar (UserStateLoggedIn sampleUser)
                            |> Query.children []
                            |> Query.first
                            |> Event.simulate Event.click
                            |> Event.toResult
                            |> Expect.err
                , test "'last checked' time updates with clock ticks" <|
                    \_ ->
                        init
                            |> Application.handleCallback
                                (Callback.ResourceFetched <|
                                    Ok
                                        { teamName = teamName
                                        , pipelineName = pipelineName
                                        , name = resourceName
                                        , failingToCheck = False
                                        , checkError = ""
                                        , checkSetupError = ""
                                        , lastChecked = Just (Time.millisToPosix 0)
                                        , pinnedVersion = Nothing
                                        , pinnedInConfig = False
                                        , pinComment = Nothing
                                        , icon = Nothing
                                        }
                                )
                            |> Tuple.first
                            |> Application.update
                                (Msgs.DeliveryReceived <|
                                    ClockTicked OneSecond <|
                                        Time.millisToPosix (2 * 1000)
                                )
                            |> Tuple.first
                            |> queryView
                            |> Query.find [ id "last-checked" ]
                            |> Query.has [ text "2s ago" ]
                , test "'last checked' tooltip respects timezone" <|
                    \_ ->
                        init
                            |> Application.handleCallback
                                (Callback.ResourceFetched <|
                                    Ok
                                        { teamName = teamName
                                        , pipelineName = pipelineName
                                        , name = resourceName
                                        , failingToCheck = False
                                        , checkError = ""
                                        , checkSetupError = ""
                                        , lastChecked =
                                            Just
                                                (Time.millisToPosix 0)
                                        , pinnedVersion = Nothing
                                        , pinnedInConfig = False
                                        , pinComment = Nothing
                                        , icon = Nothing
                                        }
                                )
                            |> Tuple.first
                            |> Application.handleCallback
                                (Callback.GotCurrentTimeZone <|
                                    Time.customZone (5 * 60) []
                                )
                            |> Tuple.first
                            |> Application.update
                                (Msgs.DeliveryReceived <|
                                    ClockTicked OneSecond <|
                                        Time.millisToPosix 1000
                                )
                            |> Tuple.first
                            |> queryView
                            |> Query.find [ id "last-checked" ]
                            |> Query.has
                                [ attribute <|
                                    Attr.title "Jan 1 1970 05:00:00 AM"
                                ]
                ]
            , test "unsuccessful check shows a warning icon on the right" <|
                \_ ->
                    init
                        |> Application.handleCallback
                            (Callback.ResourceFetched <|
                                Ok
                                    { teamName = teamName
                                    , pipelineName = pipelineName
                                    , name = resourceName
                                    , failingToCheck = True
                                    , checkError = "some error"
                                    , checkSetupError = ""
                                    , lastChecked = Nothing
                                    , pinnedVersion = Nothing
                                    , pinnedInConfig = False
                                    , pinComment = Nothing
                                    , icon = Nothing
                                    }
                            )
                        |> Tuple.first
                        |> queryView
                        |> Query.find [ class "resource-check-status" ]
                        |> Query.has
                            (iconSelector
                                { size = "28px"
                                , image = Assets.ExclamationTriangleIcon
                                }
                                ++ [ style "background-size" "14px 14px"
                                   , containing [ text "some error" ]
                                   ]
                            )
            ]
        ]


csrfToken : String
csrfToken =
    "csrf_token"


flags : Application.Flags
flags =
    { turbulenceImgSrc = ""
    , notFoundImgSrc = ""
    , csrfToken = csrfToken
    , authToken = ""
    , pipelineRunningKeyframes = ""
    }


init : Application.Model
init =
    Common.init
        ("/teams/"
            ++ teamName
            ++ "/pipelines/"
            ++ pipelineName
            ++ "/resources/"
            ++ resourceName
        )


update :
    Message.Message.Message
    -> Application.Model
    -> ( Application.Model, List Effects.Effect )
update =
    Msgs.Update >> Application.update


givenUserIsAuthorized : Application.Model -> Application.Model
givenUserIsAuthorized =
    Application.handleCallback
        (Callback.UserFetched <|
            Ok
                { id = "test"
                , userName = "test"
                , name = "test"
                , email = "test"
                , isAdmin = False
                , teams =
                    Dict.fromList
                        [ ( teamName, [ "member" ] )
                        ]
                }
        )
        >> Tuple.first


givenResourcePinnedStatically : Application.Model -> Application.Model
givenResourcePinnedStatically =
    Application.handleCallback
        (Callback.ResourceFetched <|
            Ok
                { teamName = teamName
                , pipelineName = pipelineName
                , name = resourceName
                , failingToCheck = False
                , checkError = ""
                , checkSetupError = ""
                , lastChecked = Nothing
                , pinnedVersion = Just (Dict.fromList [ ( "version", version ) ])
                , pinnedInConfig = True
                , pinComment = Nothing
                , icon = Nothing
                }
        )
        >> Tuple.first


givenResourcePinnedDynamically : Application.Model -> Application.Model
givenResourcePinnedDynamically =
    Application.handleCallback
        (Callback.ResourceFetched <|
            Ok
                { teamName = teamName
                , pipelineName = pipelineName
                , name = resourceName
                , failingToCheck = False
                , checkError = ""
                , checkSetupError = ""
                , lastChecked = Nothing
                , pinnedVersion = Just (Dict.fromList [ ( "version", version ) ])
                , pinnedInConfig = False
                , pinComment = Nothing
                , icon = Nothing
                }
        )
        >> Tuple.first


whenResourceLoadsWithPinnedComment : Application.Model -> ( Application.Model, List Effects.Effect )
whenResourceLoadsWithPinnedComment =
    Application.handleCallback
        (Callback.ResourceFetched <|
            Ok
                { teamName = teamName
                , pipelineName = pipelineName
                , name = resourceName
                , failingToCheck = False
                , checkError = ""
                , checkSetupError = ""
                , lastChecked = Nothing
                , pinnedVersion =
                    Just (Dict.fromList [ ( "version", version ) ])
                , pinnedInConfig = False
                , pinComment = Just "some pin comment"
                , icon = Nothing
                }
        )


givenResourcePinnedWithComment : Application.Model -> Application.Model
givenResourcePinnedWithComment =
    whenResourceLoadsWithPinnedComment >> Tuple.first


givenResourceIsNotPinned : Application.Model -> Application.Model
givenResourceIsNotPinned =
    Application.handleCallback
        (Callback.ResourceFetched <|
            Ok
                { teamName = teamName
                , pipelineName = pipelineName
                , name = resourceName
                , failingToCheck = False
                , checkError = ""
                , checkSetupError = ""
                , lastChecked = Just (Time.millisToPosix 0)
                , pinnedVersion = Nothing
                , pinnedInConfig = False
                , pinComment = Nothing
                , icon = Nothing
                }
        )
        >> Tuple.first


givenResourceHasIcon : Application.Model -> Application.Model
givenResourceHasIcon =
    Application.handleCallback
        (Callback.ResourceFetched <|
            Ok
                { teamName = teamName
                , pipelineName = pipelineName
                , name = resourceName
                , failingToCheck = False
                , checkError = ""
                , checkSetupError = ""
                , lastChecked = Just (Time.millisToPosix 0)
                , pinnedVersion = Nothing
                , pinnedInConfig = False
                , pinComment = Nothing
                , icon = Just resourceIcon
                }
        )
        >> Tuple.first


hoverOverPinBar : Application.Model -> Application.Model
hoverOverPinBar =
    update (Message.Message.Hover <| Just Message.Message.PinBar)
        >> Tuple.first


hoverOverPinButton : Application.Model -> Application.Model
hoverOverPinButton =
    update (Message.Message.Hover <| Just <| Message.Message.PinButton versionID)
        >> Tuple.first


clickToPin : Models.VersionId -> Application.Model -> Application.Model
clickToPin vid =
    update (Message.Message.Click <| Message.Message.PinButton vid)
        >> Tuple.first


clickToUnpin : Application.Model -> Application.Model
clickToUnpin =
    update (Message.Message.Click <| Message.Message.PinButton versionID)
        >> Tuple.first


clickToDisable : Models.VersionId -> Application.Model -> Application.Model
clickToDisable vid =
    update (Message.Message.Click <| Message.Message.VersionToggle vid)
        >> Tuple.first


givenVersionsWithoutPagination : Application.Model -> Application.Model
givenVersionsWithoutPagination =
    Application.handleCallback
        (Callback.VersionedResourcesFetched <|
            Ok
                ( Nothing
                , { content =
                        [ { id = versionID.versionID
                          , version = Dict.fromList [ ( "version", version ) ]
                          , metadata = []
                          , enabled = True
                          }
                        , { id = otherVersionID.versionID
                          , version = Dict.fromList [ ( "version", otherVersion ) ]
                          , metadata = []
                          , enabled = True
                          }
                        , { id = disabledVersionID.versionID
                          , version = Dict.fromList [ ( "version", disabledVersion ) ]
                          , metadata = []
                          , enabled = False
                          }
                        ]
                  , pagination =
                        { previousPage = Nothing
                        , nextPage = Nothing
                        }
                  }
                )
        )
        >> Tuple.first


givenVersionsWithPagination : Application.Model -> Application.Model
givenVersionsWithPagination =
    Application.handleCallback
        (Callback.VersionedResourcesFetched <|
            Ok
                ( Nothing
                , { content =
                        [ { id = versionID.versionID
                          , version = Dict.fromList [ ( "version", version ) ]
                          , metadata = []
                          , enabled = True
                          }
                        , { id = otherVersionID.versionID
                          , version = Dict.fromList [ ( "version", otherVersion ) ]
                          , metadata = []
                          , enabled = True
                          }
                        , { id = disabledVersionID.versionID
                          , version = Dict.fromList [ ( "version", disabledVersion ) ]
                          , metadata = []
                          , enabled = False
                          }
                        ]
                  , pagination =
                        { previousPage =
                            Just
                                { direction = Since 1
                                , limit = 1
                                }
                        , nextPage =
                            Just
                                { direction = Since 100
                                , limit = 1
                                }
                        }
                  }
                )
        )
        >> Tuple.first


givenTextareaFocused : Application.Model -> Application.Model
givenTextareaFocused =
    update Message.Message.FocusTextArea
        >> Tuple.first


givenTextareaBlurred : Application.Model -> Application.Model
givenTextareaBlurred =
    update Message.Message.BlurTextArea
        >> Tuple.first


pressEnterKey :
    Application.Model
    -> ( Application.Model, List Effects.Effect )
pressEnterKey =
    Application.update
        (Msgs.DeliveryReceived <|
            KeyDown
                { ctrlKey = False
                , shiftKey = False
                , metaKey = False
                , code = Keyboard.Enter
                }
        )


pressControlEnter :
    Application.Model
    -> ( Application.Model, List Effects.Effect )
pressControlEnter =
    Application.update
        (Msgs.DeliveryReceived <|
            KeyDown
                { ctrlKey = True
                , shiftKey = False
                , metaKey = False
                , code = Keyboard.Enter
                }
        )


pressMetaEnter :
    Application.Model
    -> ( Application.Model, List Effects.Effect )
pressMetaEnter =
    Application.update
        (Msgs.DeliveryReceived <|
            KeyDown
                { ctrlKey = False
                , shiftKey = False
                , metaKey = True
                , code = Keyboard.Enter
                }
        )


commentBar : Application.Model -> Query.Single Msgs.TopLevelMessage
commentBar =
    queryView
        >> Query.find [ id "comment-bar" ]


versionSelector : String -> List Selector
versionSelector v =
    anyVersionSelector ++ [ containing [ text v ] ]


anyVersionSelector : List Selector
anyVersionSelector =
    [ tag "li" ]


pinButtonSelector : List Selector
pinButtonSelector =
    [ attribute (Attr.attribute "aria-label" "Pin Resource Version") ]


pointerCursor : List Selector
pointerCursor =
    [ style "cursor" "pointer" ]


defaultCursor : List Selector
defaultCursor =
    [ style "cursor" "default" ]


checkboxSelector : List Selector
checkboxSelector =
    [ attribute (Attr.attribute "aria-label" "Toggle Resource Version Enabled") ]


hasCheckbox : Query.Single msg -> Expectation
hasCheckbox =
    Query.findAll checkboxSelector
        >> Query.count (Expect.equal 1)


purpleOutlineSelector : List Selector
purpleOutlineSelector =
    [ style "border" <| "1px solid " ++ purpleHex ]


redOutlineSelector : List Selector
redOutlineSelector =
    [ style "border" <| "1px solid " ++ failureRed ]


findLast : List Selector -> Query.Single msg -> Query.Single msg
findLast selectors =
    Query.findAll selectors >> Query.index -1


pinBarTooltipSelector : List Selector
pinBarTooltipSelector =
    [ id "pin-bar-tooltip" ]


versionTooltipSelector : List Selector
versionTooltipSelector =
    [ style "position" "absolute"
    , style "bottom" "25px"
    , style "background-color" tooltipGreyHex
    , style "z-index" "2"
    , style "padding" "5px"
    , style "width" "170px"
    , containing [ text "enable via pipeline config" ]
    ]


pinButtonHasTransitionState : Query.Single msg -> Expectation
pinButtonHasTransitionState =
    Expect.all
        [ Query.has loadingSpinnerSelector
        , Query.hasNot
            [ style "background-image" <|
                Assets.backgroundImage <|
                    Just Assets.PinIconWhite
            ]
        ]


pinButtonHasUnpinnedState : Query.Single msg -> Expectation
pinButtonHasUnpinnedState =
    Expect.all
        [ Query.has
            [ style "background-image" <|
                Assets.backgroundImage <|
                    Just Assets.PinIconWhite
            ]
        , Query.hasNot purpleOutlineSelector
        ]


pinToolsHasTransitionState : Query.Single msg -> Expectation
pinToolsHasTransitionState =
    Query.find [ id "pin-tools" ]
        >> Expect.all
            [ Query.has [ style "border" <| "1px solid " ++ lightGreyHex ]
            , Query.findAll
                [ style "background-image" <|
                    Assets.backgroundImage <|
                        Just Assets.PinIconGrey
                ]
                >> Query.count (Expect.equal 1)
            , Query.hasNot [ tag "table" ]
            ]


pinBarHasPinnedState : String -> Query.Single msg -> Expectation
pinBarHasPinnedState v =
    Query.find [ id "pin-bar" ]
        >> Expect.all
            [ Query.has [ text v ]
            , Query.findAll
                [ style "background-image" <|
                    Assets.backgroundImage <|
                        Just Assets.PinIconWhite
                ]
                >> Query.count (Expect.equal 1)
            ]


loadingSpinnerSelector : List Selector
loadingSpinnerSelector =
    [ style "animation" "container-rotate 1568ms linear infinite"
    , style "height" "12.5px"
    , style "width" "12.5px"
    , style "margin" "6.25px"
    ]


checkboxHasTransitionState : Query.Single msg -> Expectation
checkboxHasTransitionState =
    Expect.all
        [ Query.has loadingSpinnerSelector
        , Query.hasNot
            [ style "background-image" <|
                Assets.backgroundImage <|
                    Just Assets.CheckmarkIcon
            ]
        ]


checkboxHasDisabledState : Query.Single msg -> Expectation
checkboxHasDisabledState =
    Expect.all
        [ Query.hasNot loadingSpinnerSelector
        , Query.hasNot
            [ style "background-image" <|
                Assets.backgroundImage <|
                    Just Assets.CheckmarkIcon
            ]
        ]


checkboxHasEnabledState : Query.Single msg -> Expectation
checkboxHasEnabledState =
    Expect.all
        [ Query.hasNot loadingSpinnerSelector
        , Query.has
            [ style "background-image" <|
                Assets.backgroundImage <|
                    Just Assets.CheckmarkIcon
            ]
        ]


versionHasDisabledState : Query.Single msg -> Expectation
versionHasDisabledState =
    Expect.all
        [ Query.has [ style "opacity" "0.5" ]
        , Query.find checkboxSelector
            >> checkboxHasDisabledState
        ]


session : Session
session =
    { userState =
        UserStateLoggedIn
            { id = "test"
            , userName = "test"
            , name = "test"
            , email = "test"
            , isAdmin = False
            , teams = Dict.fromList [ ( teamName, [ "member" ] ) ]
            }
    , hovered = HoverState.NoHover
    , clusterName = ""
    , version = ""
    , turbulenceImgSrc = flags.turbulenceImgSrc
    , notFoundImgSrc = flags.notFoundImgSrc
    , csrfToken = flags.csrfToken
    , authToken = flags.authToken
    , pipelineRunningKeyframes = flags.pipelineRunningKeyframes
    , expandedTeams = Set.empty
    , pipelines = RemoteData.NotAsked
    , isSideBarOpen = False
    , screenSize = ScreenSize.Desktop
    , timeZone = Time.utc
    }
