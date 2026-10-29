const Cbor = 60;        //cbor

function buildBody(input) {      // Text -> Bytes
  return cbor.encode(JSON.parse(input));
}

function parseResponse(bytes) {  // Bytes -> Text
  return JSON.stringify(cbor.decode(bytes));
}


// Beispiel 
// Lampe versteht nur Plain z.B 1; 200 (an/aus; Helligkeit 0-255)
// Plain ausgewählt (0)
// PUT {"on": true, "brightness": 80}

const contentFormatPlain = 0;         // text/plain

function buildBody(input) {
  const d = JSON.parse(input);
  return (d.on ? "1" : "0") + ";" + Math.round(d.brightness * 2.55);
}