import paramiko

def generate_create_ssh_keypair(key_filename='keys/default_key'):
    """
    Generate an SSH key pair.
    """
    print("SSH Key is {}".format(key_filename))
    try:
        key = paramiko.RSAKey.from_private_key_file(key_filename)
        public_key = f'ssh-rsa {key.get_base64()}'
    except:
        key = paramiko.RSAKey.generate(bits=3072)
        public_key = f'ssh-rsa {key.get_base64()}'
        key.write_private_key
        with open(f'{key_filename}', 'w') as private_file:
            key.write_private_key(private_file)
        with open(f'{key_filename}.pub', 'w') as public_file:
            public_file.write(f'{public_key}')
    return public_key

def main():
    public_key = generate_create_ssh_keypair()
    print(public_key)

if __name__ == "__main__":
    main()