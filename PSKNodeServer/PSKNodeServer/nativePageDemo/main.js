window.onload = (event) => {
   const debugConsole = document.getElementById("debugConsole");
   const mainCanvas = document.getElementById("mainCanvas");
   const context = mainCanvas.getContext("2d");
    const button = document.getElementById("mainButton");
   function printDebug(text) {
        debugConsole.innerHTML = "" + text;
   }

   function drawData(arrayBuffer) {
       const sizeView = new Int32Array(arrayBuffer);
       const width = sizeView[0];
       const height = sizeView[1];
       const imageBitmapViewArray = new Uint8ClampedArray(arrayBuffer, 8);
       const imageData = new ImageData(imageBitmapViewArray, width, height);
       mainCanvas.width = width;
       mainCanvas.height = height;
       context.putImageData(imageData, 0, 0);
   }
    
    function start() {
        window.opendsu_native_apis.createNativeBridge((error, bridge) => {
           if(error) {
               printDebug("ERROR");
           } else {
               printDebug("API READY");

            const numberStream = bridge.importNativePushStreamAPI("photoCapturePushStream");
               numberStream.openStream(["bgra", 5]).then(() => {
                   printDebug("Number stream opened");
                   numberStream.openChannel("main").then((channel) => {
                      printDebug("CHANNEL OPENED");
                       channel.setNewEventHandler((arrayBuffer) => {
                           drawData(arrayBuffer);
                       });
                   }, (error) => {
                       printDebug("CHANNEL ERROR: " + error);
                   });
               });
           }
        });
    }
    
    button.onclick = () => {
      start();
    };
};

