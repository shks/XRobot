package org.xtext.mindstorms.xrobot.tests

import lejos.hardware.BrickFinder
import org.xtext.mindstorms.xrobot.Robot

class WeaponTest {
	def static void main(String[] args) {
		val robot = new Robot(BrickFinder.getDefault)
		robot.travelSpeed = robot.maxTravelSpeed
		while (!robot.escapePressed) {
			robot.travelBackward(30)
			robot.travelForward(30)
			robot.travelBackward(30)
			robot.travelForward(30)
			robot.travelBackward(30)
			robot.travelForward(30)
			Thread.sleep(400)			
			robot.curveForward(20, 360)
			Thread.sleep(400)
			robot.rotate(360)
			Thread.sleep(400)			
		}
	}
}