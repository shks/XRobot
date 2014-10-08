package org.xtext.xrobot.game.tests

import com.google.inject.Binder
import com.google.inject.Module
import org.xtext.xrobot.game.IErrorReporter
import org.xtext.xrobot.game.IGameListener
import org.xtext.xrobot.game.IRobotPreparer
import org.xtext.xrobot.game.IScriptPoller
import org.xtext.xrobot.game.display.Display
import org.xtext.xrobot.game.ui.GameControlWindow
import org.xtext.xrobot.server.IRemoteRobot

class XRobotTestModule implements Module {
	
	override configure(Binder binder) {
		binder.bind(IRemoteRobot.Connector).to(MockRobotConnector)
		binder.bind(IScriptPoller).to(MockScriptPoller)
		binder.bind(IRobotPreparer).to(MockRobotPreparer)
		binder.bind(IErrorReporter).to(Display)
		binder.bind(IGameListener).to(GameControlWindow)
	}
	
}