#!/bin/bash

cd ~/Blog
git pull

cp -r ta /usr/local/nginx/html

echo 'update success'
exit 0
