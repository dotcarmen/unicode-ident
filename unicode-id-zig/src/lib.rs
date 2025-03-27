#[link(name = "unicode-id")]
extern "C" {
    pub fn canStartId(c: u32) -> bool;
    pub fn canContinueId(c: u32) -> bool;
}

pub trait UnicodeCodepoint {
    fn is_xid_start(self) -> bool;
    fn is_xid_continue(self) -> bool;
}

impl UnicodeCodepoint for u32 {
    fn is_xid_start(self) -> bool {
        unsafe { canStartId(self) }
    }

    fn is_xid_continue(self) -> bool {
        unsafe { canContinueId(self) }
    }
}

impl UnicodeCodepoint for char {
    fn is_xid_start(self) -> bool {
        u32::from(self).is_xid_start()
    }

    fn is_xid_continue(self) -> bool {
        u32::from(self).is_xid_continue()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn start() {
        assert!('a'.is_xid_start());
        assert!(!' '.is_xid_start());
    }

    #[test]
    fn r#continue() {
        assert!('a'.is_xid_continue());
        assert!('1'.is_xid_continue());
        assert!(!' '.is_xid_continue());
    }
}
