%%%-------------------------------------------------------------------
%%% @doc Isotope Tree Utilities - Update elements in the UI tree.
%%% @end
%%%-------------------------------------------------------------------
-module(iso_tree).

-include("iso_elements.hrl").

-export([update/3]).

%% Update an element in the tree by ID
-spec update(term(), term(), term()) -> term().
update(#input{id = Id}, Id, NewElement) -> NewElement;
update(#button{id = Id}, Id, NewElement) -> NewElement;
update(#table{id = Id}, Id, NewElement) -> NewElement;
update(#tabs{id = Id}, Id, NewElement) -> NewElement;
update(#box{id = Id}, Id, NewElement) -> NewElement;
update(#box{children = Children} = Box, Id, NewElement) ->
    Box#box{children = [update(C, Id, NewElement) || C <- Children]};
update(#panel{children = Children} = Panel, Id, NewElement) ->
    Panel#panel{children = [update(C, Id, NewElement) || C <- Children]};
update(#vbox{children = Children} = VBox, Id, NewElement) ->
    VBox#vbox{children = [update(C, Id, NewElement) || C <- Children]};
update(#hbox{children = Children} = HBox, Id, NewElement) ->
    HBox#hbox{children = [update(C, Id, NewElement) || C <- Children]};
update(#modal{children = Children} = Modal, Id, NewElement) ->
    Modal#modal{children = [update(C, Id, NewElement) || C <- Children]};
update(#tabs{tabs = Tabs} = TabsEl, Id, NewElement) ->
    NewTabs = [update_tab(T, Id, NewElement) || T <- Tabs],
    TabsEl#tabs{tabs = NewTabs};
update(Element, _Id, _NewElement) -> Element.

update_tab(#tab{content = Content} = Tab, Id, NewElement) ->
    Tab#tab{content = [update(C, Id, NewElement) || C <- Content]}.

