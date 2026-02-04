%%%-------------------------------------------------------------------
%%% @doc Isotope Element Definitions
%%%
%%% All UI elements are records with a common base set of fields.
%%% Elements are rendered by calling Module:render(Element, Bounds).
%%%
%%% Inspired by Nitrogen/Nitro's element system.
%%% @end
%%%-------------------------------------------------------------------

-ifndef(ISO_ELEMENTS_HRL).
-define(ISO_ELEMENTS_HRL, true).

%%====================================================================
%% Base Element Fields
%%====================================================================

%% Common fields for all elements - use this macro in element records
-define(ELEMENT_BASE, 
    id = undefined :: term(),           %% Unique identifier
    module :: module(),                 %% Callback module for rendering
    x = 0 :: non_neg_integer(),         %% X position (column, 0-based)
    y = 0 :: non_neg_integer(),         %% Y position (row, 0-based)
    width = auto :: auto | pos_integer(),   %% Width (auto = fit content)
    height = auto :: auto | pos_integer(),  %% Height (auto = fit content)
    style = #{} :: map(),               %% Style properties (fg, bg, bold, etc.)
    visible = true :: boolean(),        %% Whether to render
    focusable = false :: boolean()      %% Can receive focus
).

%%====================================================================
%% Bounds Record
%%====================================================================

%% Bounds passed to render functions - defines available space
-record(bounds, {
    x = 0 :: non_neg_integer(),
    y = 0 :: non_neg_integer(),
    width = 80 :: pos_integer(),
    height = 24 :: pos_integer()
}).

%%====================================================================
%% Basic Elements
%%====================================================================

%% Text element - displays a string
-record(text, {
    ?ELEMENT_BASE,
    content = <<>> :: binary() | string()
}).

%% Box element - container with optional border
-record(box, {
    ?ELEMENT_BASE,
    border = none :: none | single | double | rounded,
    title = undefined :: undefined | binary() | string(),
    children = [] :: [tuple()]  %% Child elements
}).

%% Panel element - simple container without border
-record(panel, {
    ?ELEMENT_BASE,
    children = [] :: [tuple()]
}).

%% Horizontal box - lays out children horizontally
-record(hbox, {
    ?ELEMENT_BASE,
    spacing = 0 :: non_neg_integer(),
    children = [] :: [tuple()]
}).

%% Vertical box - lays out children vertically
-record(vbox, {
    ?ELEMENT_BASE,
    spacing = 0 :: non_neg_integer(),
    children = [] :: [tuple()]
}).

%%====================================================================
%% Interactive Elements
%%====================================================================

%% Button element - clickable, triggers event on Enter/Space
-record(button, {
    ?ELEMENT_BASE,
    label = <<>> :: binary() | string(),
    on_click = undefined :: undefined | {atom(), atom()} | fun()  %% {Module, Function} or fun()
}).

%% Input element - text input field
-record(input, {
    ?ELEMENT_BASE,
    value = <<>> :: binary() | string(),
    placeholder = <<>> :: binary() | string(),
    cursor_pos = 0 :: non_neg_integer(),
    on_change = undefined :: undefined | {atom(), atom()} | fun(),
    on_submit = undefined :: undefined | {atom(), atom()} | fun()
}).

%% Modal element - overlay that appears on top of everything
-record(modal, {
    ?ELEMENT_BASE,
    title = <<>> :: binary() | string(),
    children = [] :: [tuple()],
    border = double :: none | single | double | rounded
}).

%%====================================================================
%% Widget Elements
%%====================================================================

%% Table column definition
-record(table_col, {
    id :: term(),                          %% Column identifier
    header = <<>> :: binary() | string(),  %% Column header text
    width = auto :: auto | pos_integer(),  %% Column width
    align = left :: left | center | right  %% Text alignment
}).

%% Table element - displays tabular data with optional selection
-record(table, {
    ?ELEMENT_BASE,
    columns = [] :: [#table_col{}],        %% Column definitions
    rows = [] :: [[term()]],               %% Row data (list of lists)
    selected_row = 0 :: non_neg_integer(), %% Currently selected row (0 = none)
    scroll_offset = 0 :: non_neg_integer(),%% Vertical scroll offset
    border = none :: none | single | double,  %% Default to no border
    show_header = true :: boolean(),       %% Show column headers
    zebra = true :: boolean(),             %% Alternate row colors (default on)
    on_select = undefined :: undefined | {atom(), atom()} | fun()
}).

%% Tab definition for tabs widget
-record(tab, {
    id :: term(),                          %% Tab identifier
    label = <<>> :: binary() | string(),   %% Tab label text
    content = [] :: [tuple()]              %% Tab content (list of elements)
}).

%% Tabs element - tabbed container for switching between views
-record(tabs, {
    ?ELEMENT_BASE,
    tabs = [] :: [#tab{}],                 %% List of tab definitions
    active_tab = undefined :: term(),      %% ID of currently active tab
    tab_style = top :: top | bottom,       %% Tab bar position
    on_change = undefined :: undefined | {atom(), atom()} | fun()
}).

%%====================================================================
%% Style Helpers
%%====================================================================

%% Foreground colors
-define(FG_BLACK, #{fg => black}).
-define(FG_RED, #{fg => red}).
-define(FG_GREEN, #{fg => green}).
-define(FG_YELLOW, #{fg => yellow}).
-define(FG_BLUE, #{fg => blue}).
-define(FG_MAGENTA, #{fg => magenta}).
-define(FG_CYAN, #{fg => cyan}).
-define(FG_WHITE, #{fg => white}).

%% Background colors
-define(BG_BLACK, #{bg => black}).
-define(BG_RED, #{bg => red}).
-define(BG_GREEN, #{bg => green}).
-define(BG_YELLOW, #{bg => yellow}).
-define(BG_BLUE, #{bg => blue}).
-define(BG_MAGENTA, #{bg => magenta}).
-define(BG_CYAN, #{bg => cyan}).
-define(BG_WHITE, #{bg => white}).

%% Text styles
-define(BOLD, #{bold => true}).
-define(DIM, #{dim => true}).
-define(ITALIC, #{italic => true}).
-define(UNDERLINE, #{underline => true}).

-endif. %% ISO_ELEMENTS_HRL

