# Copyright 2019 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Implementation of apple_precompiled_resource_bundle rule."""

load(
    "@bazel_skylib//lib:dicts.bzl",
    "dicts",
)
load(
    "@bazel_skylib//lib:partial.bzl",
    "partial",
)
load(
    "@build_bazel_rules_apple//apple/internal:apple_product_type.bzl",
    "apple_product_type",
)
load(
    "@build_bazel_rules_apple//apple/internal:apple_toolchains.bzl",
    "AppleMacToolsToolchainInfo",
    "AppleXPlatToolsToolchainInfo",
)
load(
    "@build_bazel_rules_apple//apple/internal:bundling_support.bzl",
    "bundling_support",
)
load(
    "@build_bazel_rules_apple//apple/internal:features_support.bzl",
    "features_support",
)
load(
    "@build_bazel_rules_apple//apple/internal:partials.bzl",
    "partials",
)
load(
    "@build_bazel_rules_apple//apple/internal:platform_support.bzl",
    "platform_support",
)
load(
    "@build_bazel_rules_apple//apple/internal:processor.bzl",
    "processor",
)
load(
    "@build_bazel_rules_apple//apple/internal:providers.bzl",
    "new_appleresourcebundleinfo",
)
load(
    "@build_bazel_rules_apple//apple/internal:resources.bzl",
    "resources",
)
load(
    "@build_bazel_rules_apple//apple/internal:rule_attrs.bzl",
    "rule_attrs",
)
load(
    "@build_bazel_rules_apple//apple/internal:rule_support.bzl",
    "rule_support",
)

def _apple_precompiled_resource_bundle_impl(_ctx):
    # Owner to attach to the resources as they're being bucketed.
    owner = None
    bucketize_args = {}

    rule_descriptor = rule_support.rule_descriptor(
        platform_type = str(_ctx.fragments.apple.single_arch_platform.platform_type),
        product_type = apple_product_type.application,
    )

    features = features_support.compute_enabled_features(
        requested_features = _ctx.features,
        unsupported_features = _ctx.disabled_features,
    )

    apple_mac_toolchain_info = _ctx.attr._mac_toolchain[AppleMacToolsToolchainInfo]
    apple_xplat_toolchain_info = _ctx.attr._xplat_toolchain[AppleXPlatToolsToolchainInfo]

    predeclared_outputs = _ctx.outputs

    platform_prerequisites = platform_support.platform_prerequisites(
        apple_fragment = _ctx.fragments.apple,
        build_settings = apple_xplat_toolchain_info.build_settings,
        config_vars = _ctx.var,
        cpp_fragment = _ctx.fragments.cpp,
        device_families = rule_descriptor.allowed_device_families,
        explicit_minimum_deployment_os = None,
        explicit_minimum_os = None,
        features = features,
        objc_fragment = _ctx.fragments.objc,
        platform_type_string = str(_ctx.fragments.apple.single_arch_platform.platform_type),
        uses_swift = False,
        xcode_version_config = _ctx.attr._xcode_config[apple_common.XcodeVersionConfig],
    )

    bundle_name, bundle_extension = bundling_support.bundle_full_name(
        custom_bundle_name = _ctx.attr.bundle_name,
        label_name = _ctx.label.name,
        rule_descriptor = rule_descriptor,
    )
    bundle_id = _ctx.attr.bundle_id or None

    apple_resource_infos = []
    process_args = {
        "actions": _ctx.actions,
        "apple_mac_toolchain_info": _ctx.attr._mac_toolchain[AppleMacToolsToolchainInfo],
        "bundle_id": bundle_id,
        "product_type": rule_descriptor.product_type,
        "rule_label": _ctx.label,
    }

    infoplists = resources.collect(
        attr = _ctx.attr,
        res_attrs = ["infoplists"],
    )
    if infoplists:
        bucketized_owners, unowned_resources, buckets = resources.bucketize_typed_data(
            bucket_type = "infoplists",
            owner = owner,
            parent_dir_param = bundle_name,
            resources = infoplists,
            **bucketize_args
        )
        apple_resource_infos.append(
            resources.process_bucketized_data(
                bucketized_owners = bucketized_owners,
                buckets = buckets,
                platform_prerequisites = platform_prerequisites,
                processing_owner = owner,
                unowned_resources = unowned_resources,
                **process_args
            ),
        )

    resource_files = resources.collect(
        attr = _ctx.attr,
        res_attrs = ["resources"],
    )

    if resource_files:
        bucketized_owners, unowned_resources, buckets = resources.bucketize_data(
            resources = resource_files,
            owner = owner,
            parent_dir_param = bundle_name,
            **bucketize_args
        )
        apple_resource_infos.append(
            resources.process_bucketized_data(
                bucketized_owners = bucketized_owners,
                buckets = buckets,
                platform_prerequisites = platform_prerequisites,
                processing_owner = owner,
                unowned_resources = unowned_resources,
                **process_args
            ),
        )

    structured_files = resources.collect(
        attr = _ctx.attr,
        res_attrs = ["structured_resources"],
    )
    if structured_files:
        if bundle_name:
            structured_parent_dir_param = partial.make(
                resources.structured_resources_parent_dir,
                parent_dir = bundle_name,
            )
        else:
            structured_parent_dir_param = partial.make(
                resources.structured_resources_parent_dir,
            )

        # Avoid processing PNG files that are referenced through the structured_resources
        # attribute. This is mostly for legacy reasons and should get cleaned up in the future.
        bucketized_owners, unowned_resources, buckets = resources.bucketize_data(
            allowed_buckets = ["strings", "plists"],
            owner = owner,
            parent_dir_param = structured_parent_dir_param,
            resources = structured_files,
            **bucketize_args
        )
        apple_resource_infos.append(
            resources.process_bucketized_data(
                bucketized_owners = bucketized_owners,
                buckets = buckets,
                platform_prerequisites = platform_prerequisites,
                processing_owner = owner,
                unowned_resources = unowned_resources,
                **process_args
            ),
        )

    top_level_resources = resources.collect(
        attr = _ctx.attr,
        res_attrs = [
            "resources",
        ],
    )

    label = _ctx.label
    actions = _ctx.actions

    processor_partials = [
        partials.resources_partial(
            actions = actions,
            apple_mac_toolchain_info = apple_mac_toolchain_info,
            bundle_extension = bundle_extension,
            bundle_id = bundle_id,
            bundle_name = bundle_name,
            environment_plist = _ctx.file._environment_plist,
            executable_name = bundle_name,
            launch_storyboard = None,
            platform_prerequisites = platform_prerequisites,
            resource_deps = getattr(_ctx.attr, "deps", []) + _ctx.attr.resources + _ctx.attr.structured_resources,
            rule_descriptor = rule_descriptor,
            rule_label = label,
            top_level_infoplists = infoplists,
            top_level_resources = top_level_resources,
            version = [],
            version_keys_required = False,
        ),
    ]

    processor_result = processor.process(
        actions = actions,
        apple_mac_toolchain_info = apple_mac_toolchain_info,
        apple_xplat_toolchain_info = apple_xplat_toolchain_info,
        bundle_name = bundle_name,
        partials = processor_partials,
        platform_prerequisites = platform_prerequisites,
        rule_descriptor = rule_descriptor,
        rule_label = label,
        bundle_extension = bundle_extension,
        features = features,
        predeclared_outputs = predeclared_outputs,
        process_and_sign_template = apple_mac_toolchain_info.process_and_sign_template,
        codesignopts = [],
        bundle_post_process_and_sign = True,
    )

    return [
        # TODO(b/122578556): Remove this ObjC provider instance.
        apple_common.new_objc_provider(),
        CcInfo(),
        new_appleresourcebundleinfo(),
        DefaultInfo(
            files = processor_result.output_files,
        ),
        OutputGroupInfo(
            bundle = processor_result.output_files,
            # **outputs.merge_output_groups(
            #     processor_result.output_groups,
            # )
        ),
    ]  # +processor_result.providers

apple_precompiled_resource_bundle = rule(
    implementation = _apple_precompiled_resource_bundle_impl,
    fragments = ["apple", "cpp", "objc"],
    outputs = {"archive": "%{name}.bundle"},
    attrs = dicts.add(
        {
            "bundle_id": attr.string(
                doc = """
The bundle ID for this target. It will replace `$(PRODUCT_BUNDLE_IDENTIFIER)` found in the files
from defined in the `infoplists` paramter.
""",
            ),
            "bundle_name": attr.string(
                doc = """
The desired name of the bundle (without the `.bundle` extension). If this attribute is not set,
then the `name` of the target will be used instead.
""",
            ),
            "infoplists": attr.label_list(
                allow_empty = True,
                allow_files = True,
                doc = """
A list of `.plist` files that will be merged to form the `Info.plist` that represents the extension.
At least one file must be specified.
Please see [Info.plist Handling](/doc/common_info.md#infoplist-handling") for what is supported.

Duplicate keys between infoplist files
will cause an error if and only if the values conflict.
Bazel will perform variable substitution on the Info.plist file for the following values (if they
are strings in the top-level dict of the plist):

${BUNDLE_NAME}: This target's name and bundle suffix (.bundle or .app) in the form name.suffix.
${PRODUCT_NAME}: This target's name.
${TARGET_NAME}: This target's name.
The key in ${} may be suffixed with :rfc1034identifier (for example
${PRODUCT_NAME::rfc1034identifier}) in which case Bazel will replicate Xcode's behavior and replace
non-RFC1034-compliant characters with -.
""",
            ),
            "resources": attr.label_list(
                allow_empty = True,
                allow_files = True,
                doc = """
Files to include in the resource bundle. Files that are processable resources, like .xib,
.storyboard, .strings, .png, and others, will be processed by the Apple bundling rules that have
those files as dependencies. Other file types that are not processed will be copied verbatim. These
files are placed in the root of the resource bundle (e.g. `Payload/foo.app/bar.bundle/...`) in most
cases. However, if they appear to be localized (i.e. are contained in a directory called *.lproj),
they will be placed in a directory of the same name in the app bundle.

You can also add other `apple_precompiled_resource_bundle` and `apple_bundle_import` targets into `resources`,
and the resource bundle structures will be propagated into the final bundle.
""",
            ),
            "structured_resources": attr.label_list(
                allow_empty = True,
                allow_files = True,
                doc = """
Files to include in the final resource bundle. They are not processed or compiled in any way
besides the processing done by the rules that actually generate them. These files are placed in the
bundle root in the same structure passed to this argument, so `["res/foo.png"]` will end up in
`res/foo.png` inside the bundle.
""",
            ),
            "_environment_plist": attr.label(
                allow_single_file = True,
                default = "@build_bazel_rules_apple//apple/internal:environment_plist_ios",
            ),
        },
        rule_attrs.common_tool_attrs(),
    ),
    doc = """
This rule encapsulates a target which is provided to dependers as a bundle. An
`apple_precompiled_resource_bundle`'s resources are put in a resource bundle in the top
level Apple bundle dependent. apple_precompiled_resource_bundle targets need to be added to
library targets through the `data` attribute.
""",
)