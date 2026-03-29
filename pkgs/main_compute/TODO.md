# TODO

- [ ] Refine pipeline logic
- [ ] Conditional compilation to assist testing on the PC
    - [ ] Conditionally substitute GPIO dependency (this would fail on the pc) 
    - [ ] Conditionally substitute Camera dependency (this would fail if there is no webcam connected)
    - [ ] Logging level needs to be baked in (though perhaps this can be runtime derived)
- [ ] Motor control logic in mainLoop (right now it's just a clean passthrough)
