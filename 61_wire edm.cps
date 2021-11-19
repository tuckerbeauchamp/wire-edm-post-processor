/**
  Copyright (C) 2007-2011 by HSMWorks ApS
  All rights reserved.

  Wire EDM post processor configuration.

  $Revision: 24479 $
  $Date: 2011-03-19 18:47:52 +0100 (lø, 19 mar 2011) $
*/

description = "2D Wire EDM";
vendor = "HSMWorks ApS";
vendorUrl = "http://www.hsmworks.com";
legal = "Copyright (C) 2007-2011 HSMWorks ApS";
certificationLevel = 2;
minimumRevision = 24000;

extension = "nc";
setCodePage("ascii");

tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.01, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = true;
allowedCircularPlanes = undefined; // allow any circular motion

// user-defined properties
properties = {
  showSequenceNumbers: true, // show sequence numbers
  sequenceNumberStart: 1, // first sequence number
  sequenceNumberIncrement: 1, // increment for sequence numbers
  separateWordsWithSpace: true, // specifies that the words should be separated with a white space
};

var gFormat = createFormat({ prefix: "G", decimals: 0 });
var mFormat = createFormat({ prefix: "M", decimals: 0 });
var dFormat = createFormat({ prefix: "D", decimals: 0 });

var xyzFormat = createFormat({
  decimals: unit == MM ? 3 : 4,
  forceDecimal: true,
});
var feedFormat = createFormat({
  decimals: unit == MM ? 2 : 3,
  forceDecimal: true,
});

var xOutput = createVariable({ prefix: "X" }, xyzFormat);
var yOutput = createVariable({ prefix: "Y" }, xyzFormat);
var zOutput = createVariable({ prefix: "Z" }, xyzFormat);
var feedOutput = createVariable({ prefix: "F" }, feedFormat);

// circular output
var iOutput = createReferenceVariable({ prefix: "I", force: true }, xyzFormat);
var jOutput = createReferenceVariable({ prefix: "J", force: true }, xyzFormat);
var kOutput = createReferenceVariable({ prefix: "K", force: true }, xyzFormat);

var gMotionModal = createModal({}, gFormat); // modal group 1 // G0-G3, ...
var gPlaneModal = createModal(
  {
    onchange: function () {
      gMotionModal.reset();
    },
  },
  gFormat
); // modal group 2 // G17-19

var WARNING_WORK_OFFSET = 0;
var WARNING_NON_XY_ARC = 1;
var WARNING_HELICAL = 2;

// collected state
var sequenceNumber;

/**
  Writes the specified block.
*/
function writeBlock() {
  if (properties.showSequenceNumbers) {
    writeWords2("N" + sequenceNumber, arguments);
    sequenceNumber += properties.sequenceNumberIncrement;
  } else {
    writeWords(arguments);
  }
}

/**
  Output a comment.
*/
function writeComment(text) {
  writeln("; " + text);
}

function onOpen() {
  zOutput.disable();

  if (!properties.separateWordsWithSpace) {
    setWordSeparator("");
  }

  sequenceNumber = properties.sequenceNumberStart;
  writeComment(programName);

  // absolute coordinates
  writeBlock(gPlaneModal.format(17));
}

function onComment(message) {
  writeComment(message);
}

/** Force output of X, Y, and Z. */
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
}

/** Force output of X, Y, Z, A, B, C, and F on next output. */
function forceAny() {
  forceXYZ();
  feedOutput.reset();
}

function onSection() {
  // wcs
  var workOffset = currentSection.workOffset;
  if (workOffset > 0) {
    warningOnce(localize("Work offset is not used."), WARNING_WORK_OFFSET);
  }

  forceXYZ();

  {
    // pure 3D
    var remaining = currentSection.workPlane;
    if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
      error(localize("Tool orientation is not supported."));
      return;
    }
    setRotation(remaining);
  }

  setCoolant(tool.coolant);

  forceAny();

  var initialPosition = currentSection.getInitialPosition();
  writeBlock(
    gMotionModal.format(0),
    xOutput.format(initialPosition.x),
    yOutput.format(initialPosition.y)
  );

  writeBlock(dFormat.format(1));
}

function onDwell(seconds) {
  error(localize("Dwelling is not allowed."));
}

function onCycle() {
  error(localize("Cycles are not allowed."));
}

function onCyclePoint(x, y, z) {}

function onCycleEnd() {}

var pendingRadiusCompensation = -1;

function onRadiusCompensation() {
  pendingRadiusCompensation = radiusCompensation;
}

function onRapid(_x, _y, _z) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  if (x || y || z) {
    if (pendingRadiusCompensation >= 0) {
      error(
        localize(
          "Radius compensation mode cannot be changed at rapid traversal."
        )
      );
    }
    writeBlock(gMotionModal.format(0), x, y, z);
    feedOutput.reset();
  }
}

function onLinear(_x, _y, _z, feed) {
  if (pendingRadiusCompensation >= 0) {
    // ensure that we end at desired position when compensation is turned off
    xOutput.reset();
    yOutput.reset();
  }
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var f = feedOutput.format(feed);
  if (x || y || z) {
    if (pendingRadiusCompensation >= 0) {
      pendingRadiusCompensation = -1;
      switch (radiusCompensation) {
        case RADIUS_COMPENSATION_LEFT:
          writeBlock(gMotionModal.format(1), gFormat.format(41), x, y, z, f);
          break;
        case RADIUS_COMPENSATION_RIGHT:
          writeBlock(gMotionModal.format(1), gFormat.format(42), x, y, z, f);
          break;
        default:
          writeBlock(gMotionModal.format(1), gFormat.format(40), x, y, z, f);
      }
    } else {
      writeBlock(gMotionModal.format(1), x, y, z, f);
    }
  } else if (f) {
    if (getNextRecord().isMotion()) {
      // try not to output feed without motion
      feedOutput.reset(); // force feed on next line
    } else {
      writeBlock(gMotionModal.format(1), f);
    }
  }
}

function onRapid5D(_x, _y, _z, _a, _b, _c) {
  error(localize("Multi-axis toolpath is not allowed."));
}

function onLinear5D(_x, _y, _z, _a, _b, _c, feed) {
  error(localize("Multi-axis toolpath is not allowed."));
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  if (pendingRadiusCompensation >= 0) {
    error(
      "Radius compensation cannot be activated/deactivated for a circular move."
    );
  }

  if (getCircularPlane() != PLANE_XY) {
    warningOnce(
      localize("Replacing non-XY plane arc with linear move."),
      WARNING_NON_XY_ARC
    );
    onLinear(x, y, z, feed);
    return;
  }

  if (isHelical()) {
    warningOnce(
      localize("Replacing helical arc with planar arc."),
      WARNING_HELICAL
    );
  }

  var start = getCurrentPosition();

  if (isFullCircle()) {
    switch (getCircularPlane()) {
      case PLANE_XY:
        writeBlock(
          gMotionModal.format(clockwise ? 2 : 3),
          iOutput.format(cx - start.x, 0),
          jOutput.format(cy - start.y, 0),
          feedOutput.format(feed)
        );
        break;
      default:
        linearize(tolerance);
    }
  } else {
    switch (getCircularPlane()) {
      case PLANE_XY:
        writeBlock(
          gMotionModal.format(clockwise ? 2 : 3),
          xOutput.format(x),
          yOutput.format(y),
          zOutput.format(z),
          iOutput.format(cx - start.x, 0),
          jOutput.format(cy - start.y, 0),
          feedOutput.format(feed)
        );
        break;
      default:
        linearize(tolerance);
    }
  }
}

function setCoolant(coolant) {
  // disabled for now
}

var mapCommand = {
  COMMAND_STOP: 0,
  COMMAND_OPTIONAL_STOP: 1,
  COMMAND_END: 2,
};

function onCommand(command) {
  switch (command) {
    case COMMAND_COOLANT_ON:
      setCoolant(COOLANT_FLOOD);
      return;
    case COMMAND_COOLANT_OFF:
      setCoolant(COOLANT_OFF);
      return;
    case COMMAND_BREAK_CONTROL:
      return;
    case COMMAND_TOOL_MEASURE:
      return;
  }

  var stringId = getCommandStringId(command);
  var mcode = mapCommand[stringId];
  if (mcode != undefined) {
    writeBlock(mFormat.format(mcode));
  } else {
    onUnsupportedCommand(command);
  }
}

function onSectionEnd() {
  forceAny();
}

function onClose() {
  onCommand(COMMAND_COOLANT_OFF);

  writeBlock(mFormat.format(2)); // stop program
}
