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

// Replaces _class::giveloadout. One cross-script hook covers all three call
// sites -- the else branch at _playerlogic.gsc:699 and both grace-period
// class-change paths at _menus.gsc:182 and :598 -- which is what we need,
// because those two cannot be guarded by editing the file (ADR-6).
install_loadout_hook()
{
	replacefunc( maps\mp\gametypes\_class::giveloadout, ::rsg_giveloadout );
}

// Runs in place of the stock loadout, so it must be a CLEAR SLATE: weapons
// taken, action slots and perks cleared, killstreaks off, then exactly what
// we want granted. Shape follows aliens.gsc:1107-1211, which is the working
// precedent for this hook on this build.
rsg_giveloadout( team, class, loadoutonly )
{
	self takeallweapons();
	self.changingweapon = undefined;
	self.loadoutprimaryattachments = [];
	self.loadoutsecondaryattachments = [];
	maps\mp\_utility::_setactionslot( 1, "" );
	maps\mp\_utility::_setactionslot( 2, "" );
	maps\mp\_utility::_setactionslot( 3, "" );
	maps\mp\_utility::_setactionslot( 4, "" );
	maps\mp\_utility::_clearperks();

	// Killstreaks must die HERE. They are granted by the loadout we are
	// replacing, so clearing them before this point would accomplish nothing.
	self.killstreaktype = "none";
	self notify( "changed_kit" );
	self notify( "giveLoadout" );

	if ( level.rsg.primary == "" )
	{
		scripts\mp\_resurgence::rsg_log( "loadout: " + self.name + " no primary set, kit skipped" );
		return;
	}

	self giveweapon( level.rsg.primary );
	self setspawnweapon( level.rsg.primary );

	if ( level.rsg.secondary != "" )
		self giveweapon( level.rsg.secondary );

	scripts\mp\_resurgence::rsg_log( "loadout: " + self.name + " kit " + level.rsg.primary + " / " + level.rsg.secondary );
}

rsg_no_class_choice()
{
	return 0;
}

rsg_bypassclasschoice()
{
	return "class0";
}
