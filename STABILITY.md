This document describes Terra's stability policy.

# Motivation

Stability allows users to upgrade without fear that their code will
break. There is no such thing as perfectly stable software. But a
well-defined stability policy establishes the risks associated with
use of the software, and the ways such risks are communicated (e.g.,
version numbers).

Stability comes at a cost. This can include the possibility of
limiting future expansions of the software, as well as locking in poor
design decisions. There is also a human cost: for example, stress
created for the maintainers in assessing the impact of every
change. These costs are important, especially for a relatively small
community such as Terra.

Therefore this document proposes a *low stress* stability policy for
Terra. The goal is not to ensure that nothing ever breaks, but to
establish clear expectations for what changes are possible and how
they will be communicated.

Ultimately, we're learning as we go along. If something doesn't work,
we may need to update the policy. Thanks for working with us in this
process, and as usual, the best way to help is to get involved.

# Versioning

Version numbers, along with release notes, are a primary mechanism for
communicating potentially breaking changes. As of Terra version 1.0.0,
a version number MAJOR.MINOR.PATCH communicates the risk level
associated with upgrading from a given increment to the next one:

  * An increment in the MAJOR position indicates a substantial risk of
    software breaking. Users should carefully consult the release
    notes to learn what changes may be required. Maintainers should
    document any potentially breaking changes to ensure that users
    have adequate knowledge to upgrade.

    There are no current plans to ever release a version 2.0.0 of
    Terra.

    While no such changes are planned, in theory, a MAJOR increment
    could be accompanied by *silent* breaking changes. That is, the
    changes might potentially alter the behavior of user programs
    without any clear error message or warning to the user. This is
    obviously a Big Deal&trade; and is a key reason why we do not ever
    intend to release a 2.0.0 version of Terra.

  * An increment in the MINOR position indicates a small, but
    non-zero, risk of breakage. Specific anticipated scenarios are
    discussed below. Users should certainly test their software to
    ensure conformance, but can (hopefully) expect a mostly painless
    upgrade process. Maintainers should document any potentially
    breaking changes to ensure that users have adequate knowledge to
    upgrade.

    While the goal at this level is still to avoid breaking changes,
    to the extent that there are any, they should be *loud*. That is,
    any potential change of behavior should be accompanied by a
    compile error or similar, fatal diagnostic. Issuing a hard error
    ensures users cannot miss the change. As a result, users can
    upgrade without fear that their programs will change behavior
    unexpectedly. If the code compiles and runs, it should be
    compatible. Of course, even here, there is always a possibility of
    unintentional silent changes. But these would be considered bugs
    and would be reverted to maintain compatibility.

  * An increment in the PATCH position should never break user
    software. If it does, this is a bug, and should be rolled back in
    a subsequent PATCH release (and included instead in the next MINOR
    release, if any). Backwards-compatible features may still be
    included in PATCH releases as long as the maintainers reasonably
    believe such changes are low risk.

Note this is less formal than [Semantic
Versioning](https://semver.org/). The goal is to follow the spirit of
SemVer without imposing unreasonable cost on the Terra community.

# Potential Minor Breaking Changes

The following specific examples of potential breaking changes are
anticipated in MINOR releases.

  * **LLVM version support.** Terra exposes various LLVM features to
    the user. The LLVM project does not offer backwards compatibility
    between releases. Therefore, Terra's approach to stability is to
    support a range of LLVM versions, and allow the user to
    choose. However, this has a cost that grows with the number of
    versions Terra supports. To reduce this cost we periodically
    deprecate and remove support for older LLVM versions. All
    deprecations are posted publicly in our issue tracker in advance
    (usually for several months), and public input is solicited prior
    to proceeding with deprecation. Removal of any LLVM version
    requires an increment in the MINOR version of Terra.

  * **OS support.** OS changes sometimes break Terra, requiring
    periodic fixes. (macOS is a particularly bad offender here.) To
    the extent these changes are backwards compatible, we will offer
    them as PATCH releases. However, in some cases such changes may be
    backwards incompatible. In such cases, we will increment the MINOR
    version.

  * **Experimental features.** Experimental features are marked as
    such to signal to the user that they may change. Backwards
    incompatible changes to such features require a MINOR version
    increment.

  * **Keyword additions.** Keywords may be added to the language with
    a MINOR increment. This is not something we take lightly, as it
    has the risk to break existing code. However, in our experience
    with languages with stricter stability policies (that completely
    disallow keyword additions), such policies can result in a
    "keyword land rush" that may ultimately be detrimental to the
    language. On the scale of potentially breaking changes, keyword
    additions are considered less harmful because they may break code
    (by causing it to fail to compile), but never to silently change
    behavior. (Any change that had the potential to silently change
    behavior would be considered a MAJOR change, and would be
    avoided.) This is not a capability we plan to use, but one we
    outline here to set expectations.

  * **Changes to the stability policy.** Backwards incompatible
    changes to the stability policy (i.e., ones that may allow more
    breaking changes at lower version numbers) also require a MINOR
    version increment.

# Not Covered by This Policy

Some features are not covered by this stability policy, and therefore
may change even in PATCH releases.

  * **Human readable diagnostic output.** For example, the output of
    `:printpretty()`, `:disas()`, etc. The output of these functions
    are generally not intended to be parsed, and may change between
    versions. If you find a need to do so, please file an issue so
    that we can explore better ways of supporting your use case.

  * **Symbols assigned to anonymous functions, variables, etc.** (that
    do not otherwise have names set by the user). The mechanism by
    which Terra chooses these names may change between releases.

  * **Symbols assigned to functions, variables, etc. with duplicate
    names** (that is, the user set identical names for two or more
    functions/variables). The mechanism by which Terra chooses these
    names may change between releases.
