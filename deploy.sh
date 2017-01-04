#!/bin/bash

cd ~/Blog
git pull

cp index.html /usr/local/nginx/html
cp -r pics /usr/local/nginx/html
cp -r ta /usr/local/nginx/html

echo 'update success'
exit 0
