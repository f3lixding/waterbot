# TODO

- [x] Interface with the web cam from v4l (get data from the webcam via the api)
- [x] Post stream frame bytes processing
- [x] Scaffolds CV pipeline (and create an easy to use api)
- [x] Bring in OpenCV as a dep
- [x] FFI for OpenCV (cpp to zig)
- [x] Research on list of apis needed from opencv
- [x] Refine list of FFI for openzv
- [x] Plug OpenCV into scaffolding done in step 2 
    - [x] We need to come up with an abstraction for the pipeline 
    - [x] It would block on a waiter (similar to what is done in the channel implementation) 
    - [x] It would probably own a *Tx (we would probably need to change how it is passed to the dispatch thread as well)
    - [x] And it would send to mainLoop via this Tx 
    - [x] Integrate it via having it run in its own thread
    - [x] Add a test path to enable it via the web ui (this means the server would need to own an OrderSender so we should probably take it out later) 
- [x] Bottlecap targeting

