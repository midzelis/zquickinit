### TODO: improve instructions on how to build and test locally

To build local recipe builder container
```
cd build
bake.sh init
```

To build ez zbm recipes using that builder
```
cd build
bake.sh ez_zbm
```

To build enter the zbm image so you can build it manually
```
cd build
bake.sh ez_zbm_debug 
# you are now in bash prompt within image
# run the build
/bake.sh 
exit
```

To test image after its build: create a distro in a file called build/main-os.qcow2, then
```
cd build
./test.sh
exit
```