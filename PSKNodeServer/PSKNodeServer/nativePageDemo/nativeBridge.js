/*

Allowed parameters: Strings, Numbers, Arrays of String|Number
*/

const isString = (str) => {
  return typeof str === 'string' || str instanceof String
}

const isNumber = (num) => {
    return typeof num === 'number' || num instanceof Number
}

const exists = (element) => {
    return element !== null && element !== undefined;
}

class CallableObject extends Function {
  constructor() {
    super('...args', 'return this._bound._call(...args)');
    // Or without the spread/rest operator:
    // super('return this._bound._call.apply(this._bound, arguments)')
    this._bound = this.bind(this);
 
    return this._bound;
  }
  
  _call(args) {
    console.log(this, args);
  }
    
}

class StreamPacketCollector {
    constructor(reader, size) {
        this.size = size;
        this.reader = reader;
        this.buffer = new Uint8Array(size);
        this.filledCount = 0;
    }
    
    collectStartingWith(startingArray) {
        const self = this;
        const safeStart = startingArray || [];
        
        if(safeStart.length >= this.size) {
            return new Promise((resolve, reject) => {
                const filled = safeStart.slice(0, self.size);
                const extra = safeStart.slice(self.size, safeStart.length - self.size);
                resolve(filled, extra);
            });
        }
        
        (startingArray || []).forEach((element, index) => {
            self.buffer[self.filledCount] = element;
            self.filledCount += 1;
        })
        
        return new Promise((resolve, reject) => {
            function pump() {
                self.reader.read().then(({value, done}) => {
                    self.handleNewChunk(value).then((done, extra) => {
                        if (done) {
                            resolve(self.buffer, extra);
                        } else {
                            pump();
                        }
                    });
                });
            }
            pump();
        });
    }
    
    handleNewChunk(chunk) {
        const self = this;
        const safeChunk = chunk || [];
        
        if(safeChunk.length + self.filledCount >= self.size) {
            const remainingCount = self.size - self.filledCount;
            self.appendNewChunk(safeChunk.slice(0, remainingCount - 1));
            
            return new Promise((resolve, reject) => {
                const extra = safeChunk.slice(remainingCount);
                resolve(true, extra);
            });
        }
        
        self.appendNewChunk(safeChunk);
        return new Promise((resolve, reject) => {
           resolve(false);
        });
    }
    
    appendNewChunk(chunk) {
        (chunk || []).forEach((element, index) => {
            this.buffer[this.filledCount] = element;
            this.filledCount += 1;
        })
    }
}

class DataStreamApiCall {
    constructor(response) {
        this.response = response;
    }
    
    setChunkHandler(handler) {
        this.chunkHandler = handler;
        const self = this;
        
        const reader = this.response.body.getReader();
        self.reader = reader;
        
        function beginCollectingNewPacket(startingBuffer) {
            const size = new DataView(startingBuffer.buffer).getUint32(0, true);
            const collector = new StreamPacketCollector(reader, size);
            return collector.collectStartingWith(startingBuffer.slice(4));
        }
        
        function pump() {
            reader.read().then(({value, done}) => {
                if (done) {
                    return;
                }
                
                function goNext(finishedPacket, extra) {
                    handler(finishedPacket);
                    console.log("collected packet of length: " + finishedPacket.length);

                    if ((extra || []).length > 0) {
                        beginCollectingNewPacket(extra).then(goNext);
                    } else {
                        pump();
                    }
                }
                
                beginCollectingNewPacket(value).then(goNext);
            });
        }
        pump();
    }
    
    closeStream() {
        this.reader.cancel();
    }
}

class NativeApiCall extends CallableObject {
    constructor(url) {
        super();
        this.url = url;
    }

    _call(args) {
        const self = this;
        args = args || [];

        return new Promise((resolve, reject) => {
            const formData = new FormData();
            args.forEach((element, index) => {
                self.insert(element, index + '', formData);
            });
                
            self.makeApiCall(formData, resolve, reject);
        });
    }
    
    makeApiCall(formData, resultCallback, errorCallback) {
        const self = this;
        const url = this.url;
        const options = {
          method: 'POST',
          mode: 'cors',
          body: formData,
          credentials: 'include'
        };
        fetch(url, options)
        .then((response) => {
            if (!response.ok) {
              throw new Error(`HTTP error! status: ${response.status} for ${self.url} and ${formData}`);
            }
            
            const isStreamedResponse = response.headers.get("X-Stream-Header");
            
            if (isStreamedResponse && isStreamedResponse.includes("*")) {
                resultCallback(new DataStreamApiCall(response))
                return;
            }
    
            return response.json().then((jsonResponse) => {
                if(jsonResponse.error) {
                    errorCallback(jsonResponse.error);
                } else if(jsonResponse.result) {
                    self.processApiResult(jsonResponse.result, resultCallback, errorCallback);
                }
            }, errorCallback);
        }, (error) => {
            console.log("Native API Error: " + error);
        });
    }
    
    processApiResult(resultArray, resultCallback, errorCallback) {
        const self = this;
        const promises = resultArray.map(element => {
            return self.promiseFor(element, resultArray)
        });
        
        Promise.all(promises).then((values) => {
            resultCallback(values);
        }, (errorReason) => {
            errorCallback(errorReason);
        });
    }
    
    promiseFor(valueItem, results) {
        const self = this;
        return new Promise((resolve, reject) => {
            if(!exists(valueItem.type)) { reject(`Unknown result type for value ${valueItem}; ${results} in call ${self.url}`); return;}
            if(valueItem.type == "number" || valueItem.type == "string") {
                const value = valueItem.value;
                if(!exists(value) || !(isNumber(value) || isString(value))) {
                    reject(`Value in ${valueItem} is neither string nor number; ${results}, ${self.url}`);
                    return;
                }
                resolve(value);
            } else {
                if(valueItem.type == "bytes") {
                    self.downloadBytes(valueItem, results, resolve, reject);
                }
            }
        });
    }
    
    downloadBytes(bytesItem, results, resolve, reject) {
        const self = this;
        if(!bytesItem.path || !(isString(bytesItem.path))) {
            reject(`Path field non-existend or wrong type: ${bytesItem}; ${results}, ${self.url}`);
            return;
        }
        const url = bytesItem.path;
        const options = {
        method: 'GET',
        mode: 'cors',
        credentials: 'include'
        };
        fetch(url, options)
        .then((response) => {
            if (!response.ok) {
                reject(`HTTP error! status: ${response.status} for ${self.url} retrieving ${bytesItem.path}`);
            }
            
            response.blob().then((theBlob) => {
                resolve(theBlob);
            });
        });
    }
    
    insert(element, name, formData) {
        const isBasicType =
        (element instanceof Blob) ||
        isString(element) ||
        isNumber(element);
        
        if(isBasicType) {
            formData.set(name, element);
        } else {
            if(element instanceof Uint8Array) {
                formData.set(name, new Blob(element, {type : 'application/octet-stream'}));
            } else if(this.isArrayOfNumbersOrStrings(element)) {
                formData.set(name, JSON.stringify(element));
            } else {
                const message = `The value ${element} is not an instance of an accepted type. Only Number, String, [String|Number], Uint8Array and Blob are acceptable types. Api call: ${this.url}`;
                throw new Error(message);
            }
        }
    }
    
    isArrayOfNumbersOrStrings(element) {
        if(element instanceof Array) {
            return element.reduce((acc, value) => {
                return acc && (isNumber(value) || isString(value));
            }, true);
        }
        return false;
    }

}

class NativePushStreamChannel {
    constructor(websocketURL, identifier) {
        this.websocketURL = websocketURL;
        this.identifier = identifier;
    }
    
    connect() {
        let socket = new WebSocket(this.websocketURL);
        socket.binaryType = "arraybuffer";
        let self = this;
        self.socket = socket;
        return new Promise((resolve, reject) => {
            socket.onopen = (event) => {
                socket.onmessage = (message) => {
                    if(message.data == "READY") {
                        socket.onmessage = (binaryMessageEvent) => {
                            self.handleIncomingData(binaryMessageEvent);
                        }
                        resolve(self);
                    } else {
                        reject(message.data);
                    }
                };
                socket.send(self.identifier);
            };
            
            socket.onerror = (error) => {
              reject(error);
            };
        });
    }
    
    setNewEventHandler(handler) {
        this.handler = handler;
    }
    
    send(data) {
        this.socket.send(data);
    }
    
    handleIncomingData(event) {
        if(this.handler) {
            this.handler(event.data);
        }
    }
}

class NativePushStreamAPI {
    constructor(origin, name) {
        this.origin = origin;
        this.apiName = name;
        const openURL = `${origin}/pushStream/open/${name}`;
        this.openCall = new NativeApiCall(openURL)
    }
    
    openStream(options) {
        let self = this;
        return new Promise((resolve, reject) => {
            self.openCall(options).then((resultArray) => {
                resolve();
            }, (error) => {
                reject(error);
            });
        });
    }
    
    openChannel(channelName,options) {
        const openChannelURL = `${this.origin}/pushStream/connect/${this.apiName}/${channelName}`;
        let openChannelCall = new NativeApiCall(openChannelURL);
        return new Promise((resolve, reject) => {
            openChannelCall(options).then((resultArray) => {
                const wsURL = resultArray[0];
                const wsID = resultArray[1];
                const channel = new NativePushStreamChannel(wsURL, wsID);
                channel.connect().then(resolve, reject);
            }, (error) => {
                reject(error);
            });
        });
    }
}

class NativeStreamAPI {
    constructor(origin, name) {
        const baseURL = `${origin}/${name}`;
        const openURL = `${baseURL}/open`;
        const nextValueURL = `${baseURL}/nextValue`;
        const closeURL = `${baseURL}/close`;

        this.openCall = new NativeApiCall(openURL);
        this.nextValueCall = new NativeApiCall(nextValueURL);
        this.closeCall = new NativeApiCall(closeURL);
    }

    openStream(args) {
        return this.openCall(args);
    }

    retrieveNextValue(args) {
        return this.nextValueCall(args);
    }

    close() {
        return this.closeCall();
    }
}

class PSSmartWalletNativeLayer {
    constructor(origin) {
        this.nativeAPIMap = {};
        this.nativeStreamAPIMap = {};
        this.nativePushStreamAPIMap = {};
        this.origin = origin;
    }

    importNativeAPI(name) {
        const url = `${this.origin}/${name}`
        const nativeApiCall = this.nativeAPIMap[name] || new NativeApiCall(url);
        this.nativeAPIMap[name] = nativeApiCall;
        return nativeApiCall;
    }

    importNativeStreamAPI(name) {
        const api = this.nativeStreamAPIMap[name] || new NativeStreamAPI(this.origin, name);
        this.nativeStreamAPIMap[name] = api;
        return api;
    }
    
    importNativePushStreamAPI(name) {
        const api = this.nativePushStreamAPIMap[name] || new NativePushStreamAPI(this.origin, name);
        this.nativePushStreamAPIMap[name] = api;
        return api;
    }
}

function detectNativeServerUrl(callback){
    const {protocol, host} = window.location;
    let url = `${protocol}//${host}`;

    url +="/nsp";

    let called = false;
    function finish(err, result){
        if(!called){
            called = true;
            return callback(err, result);
        } else if(err){
            console.log(err);
        }
    }

    fetch(url).then((response)=>{
        return response.text();
    }, (reason)=>{
        finish(reason);
    }).then((nsp)=>{
        finish(undefined, nsp);
    }).catch((err)=>{
        finish(err);
    });
}

window.opendsu_native_apis = {
    createNativeBridge : (callback)=>{
        detectNativeServerUrl((err, nsp)=>{
            if(err){
                return callback(err);
            }
            const connector = new PSSmartWalletNativeLayer(`http://localhost:${nsp}`);
            callback(undefined, connector);
        });
    }
};

