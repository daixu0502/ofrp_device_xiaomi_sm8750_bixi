#!/usr/bin/env python3
"""Add unified clone/work-profile decryption support to TWRP's vold fork.

Android stores a random credential for a profile with a unified challenge in
gatekeeper.profile.key.  The credential is encrypted by a Keystore2 key bound
to the parent user's SID.  TWRP traditionally tries the entered parent
credential directly against the profile's synthetic-password protector, which
can never work.  This source transformation refreshes the parent Gatekeeper
auth token and unwraps the tied profile credential through Keystore2 first.
"""

from pathlib import Path
import sys


if len(sys.argv) != 2:
    raise SystemExit("usage: apply-bixi-tied-profile-fix.py <orangefox-source-root>")

path = Path(sys.argv[1]) / "system/vold/Decrypt.cpp"
if not path.is_file():
    raise SystemExit(f"OrangeFox vold Decrypt.cpp was not found at: {path}")

text = path.read_text()
legacy_markers = (
    "bixi: decrypt Android unified tied-profile credentials.",
    "bixi: decrypt Android unified tied-profile credentials (v2).",
)
marker = "bixi: decrypt Android unified tied-profile credentials (v3)."
if marker in text:
    print("bixi tied-profile decryption fix v3 is already applied.")
    raise SystemExit(0)
applied_marker = next((candidate for candidate in legacy_markers if candidate in text), None)

aidl_include = "#include <aidl/android/hardware/gatekeeper/IGatekeeper.h>\n"
hidl_include = "#include <android/hardware/gatekeeper/1.0/IGatekeeper.h>\n"
if aidl_include not in text:
    if hidl_include not in text:
        raise SystemExit("Unable to find the Gatekeeper include in system/vold/Decrypt.cpp")
    text = text.replace(hidl_include, aidl_include + hidl_include, 1)

include_anchor = "#include <openssl/evp.h>\n#include <openssl/rand.h>\n"
include_replacement = (
    "#include <openssl/evp.h>\n"
    "#include <openssl/hmac.h>\n"
    "#include <openssl/rand.h>\n"
)
if "#include <openssl/hmac.h>\n" not in text:
    if include_anchor not in text:
        raise SystemExit("Unable to find the OpenSSL include block in system/vold/Decrypt.cpp")
    text = text.replace(include_anchor, include_replacement, 1)

unwrap_anchor = "\tstd::string unwrapSyntheticPasswordBlob(const std::string& spblob_path, const std::string& handle_str, const userid_t user_id,\n"
helpers = r'''
	// bixi: decrypt Android unified tied-profile credentials (v3).
	// A tied profile's random credential is protected by a Keystore2 AES-GCM key
	// that is authorized by the parent user's Gatekeeper SID.  Refresh that
	// authorization after unwrapping the parent's synthetic password.
	bool AddSyntheticPasswordAuthToken(const userid_t user_id, const unsigned char version,
			const unsigned char* synthetic_password, const size_t synthetic_password_size) {
		std::string handle_path = "/data/system_de/" + std::to_string(user_id) +
				"/spblob/0000000000000000.handle";
		std::string handle;
		if (!android::base::ReadFileToString(handle_path, &handle) || handle.empty()) {
			printf("No synthetic-password Gatekeeper handle for user %d\n", user_id);
			return false;
		}

		std::vector<uint8_t> gatekeeper_password;
		if (version == SYNTHETIC_PASSWORD_VERSION_V3) {
			gatekeeper_password.resize(SHA256_DIGEST_LENGTH);
			HMAC_CTX ctx;
			HMAC_CTX_init(&ctx);
			if (HMAC_Init_ex(&ctx, synthetic_password, synthetic_password_size,
					EVP_sha256(), nullptr) != 1) {
				HMAC_CTX_cleanup(&ctx);
				return false;
			}
			uint32_t value = 1;
			endianswap(&value);
			HMAC_Update(&ctx, reinterpret_cast<const unsigned char*>(&value), sizeof(value));
			HMAC_Update(&ctx, reinterpret_cast<const unsigned char*>("sp-gk-authentication"),
					strlen("sp-gk-authentication"));
			const unsigned char divider = 0;
			HMAC_Update(&ctx, &divider, 1);
			HMAC_Update(&ctx, reinterpret_cast<const unsigned char*>(PERSONALISATION_CONTEXT),
					strlen(PERSONALISATION_CONTEXT));
			value = strlen(PERSONALISATION_CONTEXT) * 8;
			endianswap(&value);
			HMAC_Update(&ctx, reinterpret_cast<const unsigned char*>(&value), sizeof(value));
			value = 256;
			endianswap(&value);
			HMAC_Update(&ctx, reinterpret_cast<const unsigned char*>(&value), sizeof(value));
			unsigned int output_size = 0;
			HMAC_Final(&ctx, gatekeeper_password.data(), &output_size);
			HMAC_CTX_cleanup(&ctx);
			gatekeeper_password.resize(output_size);
		} else {
			void* derived = PersonalizedHashBinary("sp-gk-authentication",
					reinterpret_cast<const char*>(synthetic_password), synthetic_password_size);
			if (derived == nullptr)
				return false;
			gatekeeper_password.assign(reinterpret_cast<uint8_t*>(derived),
					reinterpret_cast<uint8_t*>(derived) + SHA512_DIGEST_LENGTH);
			free(derived);
		}

		auto publish_auth_token = [](const HardwareAuthToken& auth_token) {
			::ndk::SpAIBinder authz_binder(
					AServiceManager_checkService("android.security.authorization"));
			auto authorization =
					aidl::android::security::authorization::IKeystoreAuthorization::fromBinder(
						authz_binder);
			if (authorization == nullptr) {
				printf("Keystore authorization service is unavailable\n");
				return false;
			}
			auto status = authorization->addAuthToken(auth_token);
			if (!status.isOk()) {
				printf("Failed to add parent auth token: %s\n", status.getDescription().c_str());
				return false;
			}
			return true;
		};

		const char* aidl_instance = "android.hardware.gatekeeper.IGatekeeper/default";
		::ndk::SpAIBinder aidl_binder(AServiceManager_checkService(aidl_instance));
		auto aidl_gatekeeper =
				::aidl::android::hardware::gatekeeper::IGatekeeper::fromBinder(aidl_binder);
		if (aidl_gatekeeper != nullptr) {
			std::vector<uint8_t> aidl_handle(handle.begin(), handle.end());
			::aidl::android::hardware::gatekeeper::GatekeeperVerifyResponse rsp;
			auto status = aidl_gatekeeper->verify(user_id, 0, aidl_handle,
					gatekeeper_password, &rsp);
			if (!status.isOk()) {
				printf("AIDL Gatekeeper verify transaction failed: %s\n",
						status.getDescription().c_str());
				return false;
			}
			if (rsp.statusCode <
					::aidl::android::hardware::gatekeeper::IGatekeeper::STATUS_OK) {
				printf("AIDL synthetic-password Gatekeeper verification failed: %d\n",
						rsp.statusCode);
				return false;
			}
			if (!publish_auth_token(rsp.hardwareAuthToken))
				return false;
			printf("Authorized Keystore2 with AIDL Gatekeeper for user %d\n", user_id);
			return true;
		}

		auto hidl_gatekeeper =
				::android::hardware::gatekeeper::V1_0::IGatekeeper::getService();
		if (hidl_gatekeeper == nullptr) {
			printf("AIDL and HIDL Gatekeeper are unavailable while authorizing tied profiles\n");
			return false;
		}
		android::hardware::hidl_vec<uint8_t> handle_vec;
		handle_vec.setToExternal(reinterpret_cast<uint8_t*>(&handle[0]), handle.size());
		android::hardware::hidl_vec<uint8_t> password_vec;
		password_vec.setToExternal(gatekeeper_password.data(), gatekeeper_password.size());
		bool token_added = false;
		auto verify_result = hidl_gatekeeper->verify(user_id, 0, handle_vec, password_vec,
				[&token_added, &publish_auth_token](
						const android::hardware::gatekeeper::V1_0::GatekeeperResponse& rsp) {
			if (rsp.code < android::hardware::gatekeeper::V1_0::GatekeeperStatusCode::STATUS_OK ||
					rsp.data.size() < sizeof(hw_auth_token_t)) {
				printf("HIDL synthetic-password Gatekeeper verification failed\n");
				return;
			}
			const hw_auth_token_t* hw_token =
					reinterpret_cast<const hw_auth_token_t*>(rsp.data.data());
			HardwareAuthToken auth_token;
			auth_token.timestamp.milliSeconds = betoh64(hw_token->timestamp);
			auth_token.challenge = hw_token->challenge;
			auth_token.userId = hw_token->user_id;
			auth_token.authenticatorId = hw_token->authenticator_id;
			auth_token.authenticatorType = static_cast<HardwareAuthenticatorType>(
					betoh32(hw_token->authenticator_type));
			auth_token.mac.assign(&hw_token->hmac[0], &hw_token->hmac[32]);
			token_added = publish_auth_token(auth_token);
		});
		if (!verify_result.isOk() || !token_added)
			return false;
		printf("Authorized Keystore2 with HIDL Gatekeeper for user %d\n", user_id);
		return true;
	}

'''
if unwrap_anchor not in text:
    raise SystemExit("Unable to find unwrapSyntheticPasswordBlob() in system/vold/Decrypt.cpp")
if applied_marker is not None:
    helper_start = text.find("\t// " + applied_marker)
    helper_end = text.find(unwrap_anchor, helper_start)
    if helper_start < 0 or helper_end < 0:
        raise SystemExit("Unable to locate the existing tied-profile helper for upgrade")
    text = text[:helper_start] + helpers + text[helper_end:]
    old_call = 'keyDescriptor("profile_key_name_decrypt_" + std::to_string(profile_user_id))'
    new_call = '::android::keystore::keyDescriptor("profile_key_name_decrypt_" + std::to_string(profile_user_id))'
    if new_call not in text:
        if old_call not in text:
            raise SystemExit("Unable to upgrade the existing tied-profile key lookup")
        text = text.replace(old_call, new_call, 1)
    path.write_text(text)
    print("Upgraded bixi tied-profile decryption support to v3 with AIDL Gatekeeper.")
    raise SystemExit(0)
text = text.replace(unwrap_anchor, helpers + unwrap_anchor, 1)

derive_anchor = "\t\t\tif (*synthetic_password_version == SYNTHETIC_PASSWORD_VERSION_V3) {\n\t\t\t\t// V3 uses SP800 instead of SHA512\n"
derive_replacement = (
    "\t\t\tif (!AddSyntheticPasswordAuthToken(user_id, *synthetic_password_version,\n"
    "\t\t\t\t\tsecret_key, secret_key_real_size)) {\n"
    "\t\t\t\tprintf(\"Warning: could not authorize tied profiles for user %d\\n\", user_id);\n"
    "\t\t\t}\n"
    "\t\t\tif (*synthetic_password_version == SYNTHETIC_PASSWORD_VERSION_V3) {\n"
    "\t\t\t\t// V3 uses SP800 instead of SHA512\n"
)
if derive_anchor not in text:
    raise SystemExit("Unable to find the FBE-key derivation block in system/vold/Decrypt.cpp")
text = text.replace(derive_anchor, derive_replacement, 1)

password_type_anchor = 'extern "C" int Get_Password_Type(const userid_t user_id, std::string& filename) {\n'
tied_profile_helpers = r'''
	bool GetTiedProfileCredential(const userid_t profile_user_id, std::string* credential) {
		const std::string profile_lock_path = "/data/system/users/" +
				std::to_string(profile_user_id) + "/gatekeeper.profile.key";
		std::string stored_data;
		if (!android::base::ReadFileToString(profile_lock_path, &stored_data) ||
				stored_data.size() <= 12 + 16) {
			printf("Invalid tied-profile lock file for user %d\n", profile_user_id);
			return false;
		}

		::keystore::hidl_vec<uint8_t> iv;
		iv.setToExternal(reinterpret_cast<uint8_t*>(&stored_data[0]), 12);
		::keystore::hidl_vec<uint8_t> ciphertext;
		ciphertext.setToExternal(reinterpret_cast<uint8_t*>(&stored_data[12]),
				stored_data.size() - 12);
		auto params = keymint::AuthorizationSetBuilder()
				.Authorization(keymint::TAG_ALGORITHM, keymint::Algorithm::AES)
				.Authorization(keymint::TAG_BLOCK_MODE, keymint::BlockMode::GCM)
				.Padding(keymint::PaddingMode::NONE)
				.Authorization(keymint::TAG_PURPOSE, keymint::KeyPurpose::DECRYPT)
				.Authorization(keymint::TAG_NONCE, iv)
				.Authorization(keymint::TAG_MAC_LENGTH, 128);

		::ndk::SpAIBinder binder(AServiceManager_checkService(
				"android.system.keystore2.IKeystoreService/default"));
		auto keystore = ks2::IKeystoreService::fromBinder(binder);
		if (keystore == nullptr) {
			printf("Keystore2 is unavailable for tied-profile decryption\n");
			return false;
		}
		ks2::KeyEntryResponse key_entry;
		auto status = keystore->getKeyEntry(
				::android::keystore::keyDescriptor("profile_key_name_decrypt_" + std::to_string(profile_user_id)),
				&key_entry);
		if (!status.isOk()) {
			printf("Failed to get tied-profile key: %s\n", status.getDescription().c_str());
			return false;
		}
		ks2::CreateOperationResponse operation;
		status = key_entry.iSecurityLevel->createOperation(
				key_entry.metadata.key, params.vector_data(), true, &operation);
		if (!status.isOk()) {
			printf("Failed to begin tied-profile decrypt: %s\n", status.getDescription().c_str());
			return false;
		}
		std::optional<std::vector<uint8_t>> plaintext;
		status = operation.iOperation->finish(ciphertext, {}, &plaintext);
		if (!status.isOk() || !plaintext.has_value()) {
			printf("Failed to finish tied-profile decrypt: %s\n", status.getDescription().c_str());
			return false;
		}
		credential->assign(reinterpret_cast<const char*>(plaintext->data()), plaintext->size());
		printf("Recovered unified credential for profile user %d\n", profile_user_id);
		return !credential->empty();
	}

	bool DecryptTiedProfile(const userid_t profile_user_id, const std::string& parent_password) {
		std::string profile_credential;
		if (!GetTiedProfileCredential(profile_user_id, &profile_credential) &&
				parent_password != "!") {
			printf("Refreshing parent user 0 authentication for tied profile %d\n",
					profile_user_id);
			// This also publishes the parent's fresh HardwareAuthToken to Keystore2.
			(void)Decrypt_User_Synth_Pass(0, parent_password);
			if (!GetTiedProfileCredential(profile_user_id, &profile_credential))
				return false;
		}
		if (profile_credential.empty())
			return false;
		return Decrypt_User_Synth_Pass(profile_user_id, profile_credential);
	}

'''
if password_type_anchor not in text:
    raise SystemExit("Unable to find Get_Password_Type() in system/vold/Decrypt.cpp")
text = text.replace(password_type_anchor, tied_profile_helpers + password_type_anchor, 1)

user_anchor = "    std::string filename;\n    bool Default_Password = (Password == \"!\");\n"
user_replacement = (
    "\tif (user_id != 0) {\n"
    "\t\tconst std::string tied_profile_lock = \"/data/system/users/\" +\n"
    "\t\t\t\tstd::to_string(user_id) + \"/gatekeeper.profile.key\";\n"
    "\t\tif (android::vold::pathExists(tied_profile_lock)) {\n"
    "\t\t\tprintf(\"Using unified tied-profile credential path for user %d\\n\", user_id);\n"
    "\t\t\treturn DecryptTiedProfile(user_id, Password);\n"
    "\t\t}\n"
    "\t}\n"
    "    std::string filename;\n"
    "    bool Default_Password = (Password == \"!\");\n"
)
if user_anchor not in text:
    raise SystemExit("Unable to find the Decrypt_User() credential setup block")
text = text.replace(user_anchor, user_replacement, 1)

path.write_text(text)
print("Added bixi Android unified tied-profile decryption support to system/vold/Decrypt.cpp.")
