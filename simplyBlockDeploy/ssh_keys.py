import paramiko


def generate_create_ssh_keypair(namespace=None):
    """
    Generate an SSH key pair.
    """
    key_filename = "keys/{}".format(namespace)
    print("SSH Key is {}".format(key_filename))
    try:
        key = paramiko.RSAKey.from_private_key_file(key_filename)
        public_key = f'ssh-rsa {key.get_base64()}'
    except:
        key = paramiko.RSAKey.generate(bits=3072)
        public_key = f'ssh-rsa {key.get_base64()}'
        key.write_private_key_file(key_filename)
        with open(f'{key_filename}.pub', 'w') as public_file:
            public_file.write(f'{public_key}')
    return public_key


def main():
    public_key = generate_create_ssh_keypair()
    print(public_key)


if __name__ == "__main__":
    main()
