import urllib.request

url = "https://trae-api-cn.mchost.guru/api/ide/v1/text_to_image?prompt=modern%20logo%20design%20with%20letter%20H%20for%20HeinTV%2C%20minimalist%2C%20blue%20color%20scheme%2C%20digital%20tv%20theme%2C%20clean%20lines%2C%20professional%20look&image_size=square_hd"

urllib.request.urlretrieve(url, "new_logo.png")

print("Logo downloaded successfully!")