// Loadout — fixed kit, no class menu.
//
// Resurgence gives everyone the same kit, so the class-selection step should
// not exist. That is also a hard requirement rather than a nicety: a human
// client parks in waitforclassselect() (_menus.gsc:426) on
// waittill( "luinotifyserver" ) until its LUA sends "class_select", and if
// that never arrives the player never spawns and vanilla's kickifdontspawn
// (_playerlogic.gsc:1506) drops them after 90s. Observed on a real client.
//
// Bots are unaffected either way: _menus.gsc:450 handles them through the
// isBot branch, which is why bots spawned fine while a human could not.

init()
{
	// _menus.gsc:434 reads:
	//   if ( allowclasschoice() || showfakeloadout() && !isai( self ) )
	//       wait for the client's selection
	//   else
	//       bypassclasschoice()
	// Precedence is a || (b && c), so BOTH predicates must be false for a
	// human to take the bypass branch. Both live in _utility (a fastfile),
	// so they are replaced rather than edited (ADR-6).
	replacefunc( maps\mp\_utility::allowclasschoice, ::rsg_no_class_choice );
	replacefunc( maps\mp\_utility::showfakeloadout, ::rsg_no_class_choice );
}

install_callbacks()
{
	// Consumed by bypassclasschoice() at _menus.gsc:518-522.
	level.bypassclasschoicefunc = ::rsg_bypassclasschoice;
}

rsg_no_class_choice()
{
	return 0;
}

rsg_bypassclasschoice()
{
	return "class0";
}
