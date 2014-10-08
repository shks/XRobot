package org.xtext.xrobot.game.tests

import java.net.SocketTimeoutException
import org.eclipse.xtend.lib.annotations.Accessors
import org.eclipse.xtext.util.CancelIndicator
import org.xtext.xrobot.RobotID
import org.xtext.xrobot.api.Direction
import org.xtext.xrobot.api.RobotPosition
import org.xtext.xrobot.api.Sample
import org.xtext.xrobot.net.INetConfig
import org.xtext.xrobot.server.CanceledException
import org.xtext.xrobot.server.IRemoteRobot
import org.xtext.xrobot.util.AudioService

import static org.xtext.xrobot.api.GeometryExtensions.*

import static extension java.lang.Math.*

@Accessors
class MockRobot implements IRemoteRobot {

	val RobotID robotID

	val CancelIndicator cancelIndicator

	RobotPosition ownPosition

	RobotPosition opponentPosition

	double drivingSpeed

	double rotationSpeed

	extension AudioService = AudioService.getInstance 

	new(RobotID robotID, CancelIndicator cancelIndicator) {
		this.robotID = robotID
		this.cancelIndicator = cancelIndicator
		this.ownPosition = new RobotPosition(0, 0, robotID, 0)
		this.opponentPosition = new RobotPosition(0, 0, robotID.opponent, 0)
	}

	override waitForUpdate(int timeout) throws SocketTimeoutException {
		checkCanceled
		Thread.sleep(INetConfig.UPDATE_INTERVAL)
	}

	override release() {
		checkCanceled
	}

	override getBatteryState() {
		0.64
	}

	override startMotors(double leftSpeed, double rightSpeed) {
		checkCanceled
	}

	override drive(double distance) {
		checkCanceled
		ownPosition = new RobotPosition(
			ownPosition.x + distance * cos(ownPosition.viewDirection.toRadians),
			ownPosition.y + distance * sin(ownPosition.viewDirection.toRadians),
			robotID,
			ownPosition.viewDirection
		)
	}

	override driveForward() {
		checkCanceled
	}

	override driveBackward() {
		checkCanceled
	}
	
	override getMaxDrivingSpeed() {
		return 500
	}

	override rotate(double angle) {
		checkCanceled
		ownPosition = new RobotPosition(
			ownPosition.x,
			ownPosition.y,
			robotID,
			ownPosition.viewDirection + angle
		)
	}

	override rotateLeft() {
		checkCanceled
	}

	override rotateRight() {
		checkCanceled
	}

	override getMaxRotationSpeed() {
		return 500
	}

	override curveForward(double radius, double angle) {
		checkCanceled
	}

	override curveBackward(double radius, double angle) {
		checkCanceled
	}

	override curveTo(double distance, double angle) {
		checkCanceled
	}

	override isMoving() {
		checkCanceled
		false
	}

	override stop() {
		checkCanceled
	}

	override reset() {
		checkCanceled
	}

	override scoop(double angle) {
		checkCanceled
	}

	override play(Sample sample) {
		sample.play(robotID)
	}

	override say(String text) {
		text.speak(robotID)
	}

	override update() {
		checkCanceled
	}

	override getOwnPosition() {
		ownPosition
	}

	override getOpponentPosition() {
		opponentPosition
	}

	override getOpponentDirection() {
		ownPosition.getRelativeDirection(opponentPosition)
	}

	override getCenterDirection() {
		val negOwnDirection = (-ownPosition).toDirection
		new Direction(
			negOwnDirection.distance,
			normalizeAngle(negOwnDirection.angle - ownPosition.viewDirection)
		)
	}

	override getLeftMotor() {
		throw new UnsupportedOperationException("TODO: auto-generated method stub")
	}

	override getRightMotor() {
		throw new UnsupportedOperationException("TODO: auto-generated method stub")
	}

	override getScoopMotor() {
		throw new UnsupportedOperationException("TODO: auto-generated method stub")
	}

	private def checkCanceled() {
		if (cancelIndicator.isCanceled)
			throw new CanceledException
	}
	
	override getGroundColor() {
		0.6
	}
	
	override isDead() {
		false
	}
	
}